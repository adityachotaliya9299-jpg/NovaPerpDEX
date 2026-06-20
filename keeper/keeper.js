/**
 * NovaPerpDEX Keeper Bot — Phase 8.3
 *
 * Runs on a fixed interval (default 5 min). Each tick:
 *   1. Scans OrderBook for executable limit orders -> executeOrder
 *   2. Incrementally scans MarginManager's PositionIncreased event log for
 *      newly-discovered (account, market, side) tuples, merging them into a
 *      persistent watchlist on disk (state.json) so we never re-scan
 *      already-processed blocks.
 *   3. Checks the full watchlist (old + newly discovered) for executable
 *      stop-loss triggers -> executeTrigger
 *   4. Checks the full watchlist for liquidatable positions -> liquidate
 *
 * WHY EVENT-LOG REPLAY INSTEAD OF A REGISTRY CONTRACT CALL:
 * None of OrderBook/StopLossManager/MarginManager expose an on-chain
 * enumeration of "all open orders" or "all accounts with positions" — by
 * design, storing that kind of growable array on-chain is expensive and
 * usually not needed. The keeper has the opposite problem: it needs to
 * discover who to check. The standard fix is to replay the contracts' own
 * events via eth_getLogs and reconstruct a candidate set.
 *
 * WHY INCREMENTAL (state.json) INSTEAD OF RE-SCANNING EVERY TICK:
 * Free-tier RPC providers cap eth_getLogs to a tiny block range per call
 * (Alchemy free tier: 10 blocks). Re-scanning a 50,000+ block lookback
 * window every tick means tens of thousands of chunked requests, repeated
 * forever. We persist `lastScannedBlock` and the accumulated `watchlist`
 * to keeper/state.json, AND we save progress incrementally every
 * STATE_SAVE_EVERY_N_CHUNKS chunks (not just at the very end) — so if the
 * scan is interrupted (rate limit, restart, Ctrl+C) we resume from the
 * last successfully-saved block instead of starting over from zero. Only
 * the very first run ever pays the full lookback-window scan cost in
 * total; it may take several ticks to complete that first scan (resuming
 * each time from where it left off), but it does NOT restart from
 * scratch each time the way an unsaved-until-the-end approach would.
 *
 * WHY TICKS ARE REENTRANCY-GUARDED:
 * setInterval fires strictly on the clock — it does not wait for a
 * previous async tick() to finish. With a slow first scan (can take
 * longer than POLL_INTERVAL_MS), naive setInterval usage causes multiple
 * overlapping scans to run concurrently, each making their own burst of
 * RPC calls. That multiplies load against the SAME rate limit, which is
 * the most likely cause of cascading "HTTP request failed" errors during
 * a slow first scan. `isTickRunning` ensures at most one tick executes
 * at a time; if the timer fires while a tick is still in progress, that
 * tick is simply skipped (logged, not queued) and the next timer fire
 * will try again.
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
 *   4. Add environment variables: PRIVATE_KEY, RPC_URL.
 *   5. Start command: `npm start`.
 *   NOTE: Railway's filesystem is ephemeral on redeploy — state.json
 *   resets on redeploy, meaning the next tick re-pays the full lookback
 *   scan once (across multiple ticks, thanks to incremental saving — not
 *   a single giant blocking call).
 *
 * SECURITY NOTE: the keeper's private key only needs gas funds (Sepolia
 * ETH) — it does not need PRICE_KEEPER_ROLE or any privileged role, since
 * executeOrder / executeTrigger / liquidate are all permissionless. Do
 * NOT reuse your admin/deployer private key here if you can avoid it.
 */

import { createPublicClient, createWalletClient, http, parseAbiItem } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import "dotenv/config";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

import { OrderBookAbi, StopLossManagerAbi, LiquidationEngineAbi, MarginManagerAbi } from "./abis.js";
import deployment from "./deployment.json" with { type: "json" };

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const STATE_FILE = path.join(__dirname, "state.json");

// ---- config ----
const RPC_URL = process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS ?? 5 * 60 * 1000); // 5 min default
const EVENT_LOOKBACK_BLOCKS = BigInt(process.env.EVENT_LOOKBACK_BLOCKS ?? 50_000);
const LOG_CHUNK_SIZE = BigInt(process.env.LOG_CHUNK_SIZE ?? 10);
const LOG_CHUNK_DELAY_MS = Number(process.env.LOG_CHUNK_DELAY_MS ?? 300); // raised from 150 — be gentler on free-tier rate limits
const STATE_SAVE_EVERY_N_CHUNKS = Number(process.env.STATE_SAVE_EVERY_N_CHUNKS ?? 50);
const MAX_CHUNKS_PER_TICK = Number(process.env.MAX_CHUNKS_PER_TICK ?? 400); // caps how much of the backlog one tick will chew through, so a tick can't run forever and overlap the next one

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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

// ---- persistent state (lastScannedBlock + accumulated watchlist) ----
function loadState() {
  if (!fs.existsSync(STATE_FILE)) return null;
  try {
    const raw = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
    return {
      lastScannedBlock: BigInt(raw.lastScannedBlock),
      watchlist: raw.watchlist ?? [],
    };
  } catch (err) {
    log(`State file exists but failed to parse (${err.message}) — starting fresh.`);
    return null;
  }
}

function saveState(lastScannedBlock, watchlist) {
  fs.writeFileSync(
    STATE_FILE,
    JSON.stringify(
      { lastScannedBlock: lastScannedBlock.toString(), watchlist, savedAt: new Date().toISOString() },
      null,
      2
    )
  );
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
      continue;
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

// ---- watchlist: incremental discovery via PositionIncreased event replay ----
// Scans up to MAX_CHUNKS_PER_TICK chunks, saving state every
// STATE_SAVE_EVERY_N_CHUNKS chunks. If the full range isn't covered in one
// tick, the next tick resumes exactly where this one left off (the saved
// lastScannedBlock), rather than restarting the whole lookback window.
async function buildAccountWatchlist() {
  const latestBlock = await publicClient.getBlockNumber();
  const event = parseAbiItem(
    "event PositionIncreased(bytes32 key, address account, bytes32 market, uint8 side, uint256 sizeDelta, uint256 collateralDelta, uint256 price)"
  );

  const prior = loadState();
  let fromBlock;
  let watchlist;

  if (prior && prior.lastScannedBlock >= latestBlock) {
    log(`Watchlist: already up to date through block ${prior.lastScannedBlock} (${prior.watchlist.length} known entries), no new blocks to scan.`);
    return prior.watchlist;
  } else if (prior) {
    fromBlock = prior.lastScannedBlock + 1n;
    watchlist = prior.watchlist;
    log(`Watchlist: resuming scan from block ${fromBlock} (${watchlist.length} known entries so far).`);
  } else {
    fromBlock = latestBlock > EVENT_LOOKBACK_BLOCKS ? latestBlock - EVENT_LOOKBACK_BLOCKS : 0n;
    watchlist = [];
    log(`Watchlist: no prior state found, starting first scan from block ${fromBlock} (full backlog may take several ticks to cover, saving progress along the way).`);
  }

  const seen = new Set(watchlist.map((w) => `${w.account}-${w.market}-${w.side}`));
  let chunkStart = fromBlock;
  let chunksThisTick = 0;
  let newCount = 0;
  let lastSavedBlock = fromBlock > 0n ? fromBlock - 1n : 0n;

  while (chunkStart <= latestBlock && chunksThisTick < MAX_CHUNKS_PER_TICK) {
    const chunkEnd =
      chunkStart + LOG_CHUNK_SIZE - 1n > latestBlock ? latestBlock : chunkStart + LOG_CHUNK_SIZE - 1n;

    try {
      const logs = await publicClient.getLogs({
        address: marginManager.address,
        event,
        fromBlock: chunkStart,
        toBlock: chunkEnd,
      });
      for (const l of logs) {
        const { account, market, side } = l.args;
        const key = `${account}-${market}-${side}`;
        if (seen.has(key)) continue;
        seen.add(key);
        watchlist.push({ account, market, side });
        newCount++;
      }
      lastSavedBlock = chunkEnd; // only advance our "safe to resume from" marker on success
    } catch (err) {
      log(`Watchlist: chunk ${chunkStart}-${chunkEnd} failed (${err.shortMessage ?? err.message}) — will retry this range next tick.`);
      // Don't advance chunkStart/lastSavedBlock past a failed chunk — next
      // tick (or next save below) resumes from before this failure, not
      // after it, so we don't silently lose this range of blocks.
      break;
    }

    chunksThisTick++;
    chunkStart = chunkEnd + 1n;

    if (chunksThisTick % STATE_SAVE_EVERY_N_CHUNKS === 0) {
      saveState(lastSavedBlock, watchlist);
      log(`Watchlist: progress checkpoint — scanned through block ${lastSavedBlock}, ${watchlist.length} entries so far (${chunksThisTick} chunks this tick).`);
    }

    if (LOG_CHUNK_DELAY_MS > 0 && chunkStart <= latestBlock) {
      await sleep(LOG_CHUNK_DELAY_MS);
    }
  }

  saveState(lastSavedBlock, watchlist);

  const remaining = latestBlock - lastSavedBlock;
  if (remaining > 0n) {
    log(`Watchlist: tick budget reached (${chunksThisTick} chunks). Scanned through block ${lastSavedBlock}, ${remaining} block(s) remaining — will continue next tick. ${newCount} new entr${newCount === 1 ? "y" : "ies"} found this tick (${watchlist.length} total).`);
  } else {
    log(`Watchlist: caught up to latest block ${lastSavedBlock}. ${newCount} new entr${newCount === 1 ? "y" : "ies"} found this tick (${watchlist.length} total).`);
  }

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
      continue;
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

// ---- main loop (reentrancy-guarded) ----
let isTickRunning = false;

async function tick() {
  if (isTickRunning) {
    log("Tick skipped — previous tick is still running (likely still working through the watchlist backlog).");
    return;
  }
  isTickRunning = true;
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
  } finally {
    isTickRunning = false;
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