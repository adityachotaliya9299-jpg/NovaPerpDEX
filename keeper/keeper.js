/**
 * NovaPerpDEX Keeper Bot 
 *
 * Runs on a fixed interval (default 5 min). Each tick:
 *   1. Scans OrderBook for executable limit orders -> executeOrder
 *   2. Scans StopLossManager triggers for accounts with open positions ->
 *      executeTrigger
 *   3. Scans MarginManager-known accounts for liquidatable positions ->
 *      LiquidationEngine.liquidate
 *
 * WHY EVENT-LOG REPLAY INSTEAD OF A REGISTRY CONTRACT CALL: None of OrderBook/StopLossManager/MarginManager expose an on-chain of "all open orders" or "all accounts with positions" — by design, storing that kind of growable array on-chain is expensive and
 * usually not needed (the frontend reads by address, not by listing everyone). The keeper has the opposite problem: it needs to discover
 * who to check. 
 * The standard fix for this exact problem is to replay the
 * contracts' own events via eth_getLogs and reconstruct a candidate set:
 *   - OrderBook.placeOrder doesn't appear to emit an event in this ABI dump, so for order IDs we just iterate 0..nextOrderId-1, which is
 *     cheap and correct since order IDs are sequential and orders() is a simple mapping read.
 *   - For stop-loss and liquidation we don't have a similarly cheapsequential ID, so we replay MarginManager's PositionIncreased event *     to build the set of (account, market, side) tuples that have ever opened a position, then check isExecutable / isLiquidatable on each.This is a watchlist, not a perfect real-time index — a subgraph (Phase 11) is the eventual proper fix and removes this log-replay
 *     entirely, but this is more than sufficient for the current scale.
 *
 * SETUP:
 *   cd keeper
 *   npm install
 *   cp .env.example .env        # fill in PRIVATE_KEY, RPC_URL
 *   npm start
 *
 * DEPLOY (Railway, free tier):
 *   1. Push this `keeper/` folder to its own GitHub repo (or a subfolder
 *      of the existing monorepo — Railway can build from a subdirectory).
 *   2. New Railway project -> Deploy from GitHub -> select repo.
 *   3. Set the root directory to `keeper/` if using the monorepo.
 *   4. Add environment variables: PRIVATE_KEY, RPC_URL (same values as
 *      your local .env). Railway's free tier keeps this running 24/7
 *      without you touching a terminal again.
 *   5. Start command: `npm start` (Railway auto-detects this from
 *      package.json).
 *
 * SECURITY NOTE: the keeper's private key only needs gas funds (Sepolia
 * ETH) — it does not need PRICE_KEEPER_ROLE or any privileged role, since
 * executeOrder / executeTrigger / liquidate are all permissionless (any
 * caller can trigger them; the contracts pay the caller a keeper reward
 * out of the liquidation fee, see CollateralVault.keeperRewardBps from the
 * deploy script). Do NOT reuse your admin/deployer private key here if you
 * can avoid it — use a fresh wallet funded with a small amount of Sepolia
 * ETH for gas only.
 */

import { createPublicClient, createWalletClient, http, parseAbiItem } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import "dotenv/config";

import { OrderBookAbi, StopLossManagerAbi, LiquidationEngineAbi, MarginManagerAbi } from "./abis.js";
import deployment from "./deployment.json" with { type: "json" };

// ---- config ----
const RPC_URL = process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS ?? 5 * 60 * 1000); // 5 min default
const EVENT_LOOKBACK_BLOCKS = BigInt(process.env.EVENT_LOOKBACK_BLOCKS ?? 500_000); // ~ a few weeks on Sepolia's ~12s blocks

if (!RPC_URL || !PRIVATE_KEY) {
  console.error("Missing RPC_URL or PRIVATE_KEY in environment. Copy .env.example to .env and fill it in.");
  process.exit(1);
}

const account = privateKeyToAccount(PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`);

const publicClient = createPublicClient({ chain: sepolia, transport: http(RPC_URL) });
const walletClient = createWalletClient({ account, chain: sepolia, transport: http(RPC_URL) });

const orderBook = { address: deployment.OrderBook, abi: OrderBookAbi };
const stopLoss = { address: deployment.StopLossManager, abi: StopLossManagerAbi };
const liquidationEngine = { address: deployment.LiquidationEngine, abi: LiquidationEngineAbi };
const marginManager = { address: deployment.MarginManager, abi: MarginManagerAbi };

const ETH_USD_MARKET = deployment.ETH_USD;
const SIDE = { LONG: 0, SHORT: 1 };

// ---- helpers ----
function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

async function safeSend(label, fn) {
  try {
    const hash = await fn();
    log(`  -> ${label} tx sent: ${hash}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    log(`  -> ${label} ${receipt.status === "success" ? "confirmed" : "REVERTED"} (block ${receipt.blockNumber})`);
    return receipt.status === "success";
  } catch (err) {
    log(`  -> ${label} FAILED: ${err.shortMessage ?? err.message}`);
    return false;
  }
}

// ---- 1. Orders ----
async function processOrders() {
  const nextId = await publicClient.readContract({ ...orderBook, functionName: "nextOrderId" });
  if (nextId === 0n) {
    log("Orders: nextOrderId is 0, nothing placed yet.");
    return;
  }

  log(`Orders: scanning order IDs 0..${nextId - 1n} (${nextId} total)`);
  let executed = 0;

  for (let id = 0n; id < nextId; id++) {
    let order;
    try {
      order = await publicClient.readContract({ ...orderBook, functionName: "orders", args: [id] });
    } catch {
      continue; // shouldn't happen, but don't let one bad read kill the loop
    }
    const [, , , , , , , active] = order;
    if (!active) continue;

    const executable = await publicClient.readContract({
      ...orderBook,
      functionName: "isExecutable",
      args: [id],
    });
    if (!executable) continue;

    log(`Orders: order #${id} is executable, sending executeOrder...`);
    const ok = await safeSend(`executeOrder(#${id})`, () =>
      walletClient.writeContract({ ...orderBook, functionName: "executeOrder", args: [id] })
    );
    if (ok) executed++;
  }

  log(`Orders: ${executed} order(s) executed this pass.`);
}

// ---- watchlist: discover accounts via PositionIncreased event replay ----
async function buildAccountWatchlist() {
  const latestBlock = await publicClient.getBlockNumber();
  const fromBlock = latestBlock > EVENT_LOOKBACK_BLOCKS ? latestBlock - EVENT_LOOKBACK_BLOCKS : 0n;

  const logs = await publicClient.getLogs({
    address: marginManager.address,
    event: parseAbiItem(
      "event PositionIncreased(bytes32 key, address account, bytes32 market, uint8 side, uint256 sizeDelta, uint256 collateralDelta, uint256 price)"
    ),
    fromBlock,
    toBlock: latestBlock,
  });

  // De-dupe by (account, market, side) — a position can be increased many
  // times, we only need one entry per distinct position to check.
  const seen = new Set();
  const watchlist = [];
  for (const l of logs) {
    const { account, market, side } = l.args;
    const key = `${account}-${market}-${side}`;
    if (seen.has(key)) continue;
    seen.add(key);
    watchlist.push({ account, market, side });
  }

  log(`Watchlist: ${watchlist.length} distinct (account, market, side) tuples from ${logs.length} PositionIncreased events (lookback ${EVENT_LOOKBACK_BLOCKS} blocks).`);
  return watchlist;
}

// ---- 2. Stop-loss triggers ----
async function processStopLoss(watchlist) {
  let executed = 0;
  for (const { account, market, side } of watchlist) {
    let executable;
    try {
      executable = await publicClient.readContract({
        ...stopLoss,
        functionName: "isExecutable",
        args: [account, market, side],
      });
    } catch {
      continue; // no trigger set for this account/market/side — not an error
    }
    if (!executable) continue;

    log(`StopLoss: trigger executable for ${account} market=${market} side=${side}, sending executeTrigger...`);
    const ok = await safeSend(`executeTrigger(${account})`, () =>
      walletClient.writeContract({
        ...stopLoss,
        functionName: "executeTrigger",
        args: [account, market, side],
      })
    );
    if (ok) executed++;
  }
  log(`StopLoss: ${executed} trigger(s) executed this pass.`);
}

// ---- 3. Liquidations ----
async function processLiquidations(watchlist) {
  let liquidated = 0;
  for (const { account, market, side } of watchlist) {
    let liquidatable;
    try {
      liquidatable = await publicClient.readContract({
        ...marginManager,
        functionName: "isLiquidatable",
        args: [account, market, side],
      });
    } catch {
      continue;
    }
    if (!liquidatable) continue;

    log(`Liquidation: ${account} market=${market} side=${side} is liquidatable, sending liquidate...`);
    const ok = await safeSend(`liquidate(${account})`, () =>
      walletClient.writeContract({
        ...liquidationEngine,
        functionName: "liquidate",
        args: [account, market, side],
      })
    );
    if (ok) liquidated++;
  }
  log(`Liquidation: ${liquidated} position(s) liquidated this pass.`);
}

// ---- main loop ----
async function tick() {
  log("=== Keeper tick start ===");
  try {
    const paused = await publicClient.readContract({ ...liquidationEngine, functionName: "paused" });
    if (paused) {
      log("LiquidationEngine is paused — skipping liquidation pass, still processing orders/stop-loss.");
    }

    await processOrders();

    const watchlist = await buildAccountWatchlist();
    await processStopLoss(watchlist);
    if (!paused) {
      await processLiquidations(watchlist);
    }
  } catch (err) {
    log(`Tick error (will retry next interval): ${err.message}`);
  }
  log("=== Keeper tick end ===\n");
}

log(`NovaPerp keeper starting. Account: ${account.address}`);
log(`Polling every ${POLL_INTERVAL_MS / 1000}s. RPC: ${RPC_URL}`);
log(`OrderBook: ${orderBook.address}`);
log(`StopLossManager: ${stopLoss.address}`);
log(`LiquidationEngine: ${liquidationEngine.address}`);
log(`MarginManager: ${marginManager.address}`);

tick();
setInterval(tick, POLL_INTERVAL_MS);