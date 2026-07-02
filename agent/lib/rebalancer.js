/**
 * Core rebalancing logic for a single StrategyVault.
 *
 * The rebalancer:
 *   1. Reads currentTargets from the vault (JSON weights set by the LLM layer)
 *   2. Reads current on-chain positions owned by the vault
 *   3. Computes drift: how far each position is from its target weight
 *   4. If drift exceeds MIN_DRIFT_BPS_TO_REBALANCE, executes the rebalance
 *   5. Emits a structured reason string with each trade
 *
 */

const logger = require("./logger");

const WAD = BigInt("1000000000000000000"); // 1e18
const BPS = 10000n;

const MIN_DRIFT_BPS = BigInt(
  process.env.MIN_DRIFT_BPS_TO_REBALANCE ?? "500"
);

const MARKETS = {
  "ETH-USD": process.env.ETH_USD_MARKET,
  "BTC-USD": process.env.BTC_USD_MARKET,
};

const SIDE_LONG = 0;
const SIDE_SHORT = 1;

/**
 * Parse the currentTargets string from the vault.
 * Returns [] on any parse error — safer than crashing the agent.
 */
function parseTargets(targetsJson) {
  if (!targetsJson || targetsJson.trim() === "") return [];
  try {
    const parsed = JSON.parse(targetsJson);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (t) =>
        typeof t.market === "string" &&
        typeof t.side === "number" &&
        typeof t.targetWeightBps === "number" &&
        t.targetWeightBps >= 0 &&
        t.targetWeightBps <= 10000
    );
  } catch {
    return [];
  }
}

/**
 * Compute the drift in basis points between the current position size
 * and the target size, as a fraction of total vault NAV.
 */
function computeDriftBps(currentSize, targetSize, totalNAV) {
  if (totalNAV === 0n) return 0n;
  const diff = currentSize > targetSize
    ? currentSize - targetSize
    : targetSize - currentSize;
  return (diff * BPS) / totalNAV;
}

/**
 * Format a WAD bigint as a human-readable USD string.
 */
function formatUSD(wad) {
  return "$" + (Number(wad) / 1e18).toFixed(2);
}

/**
 * Run one rebalance cycle for a single vault.
 *
 * @param {object} opts
 * @param {object} opts.publicClient — viem public client
 * @param {object} opts.walletClient — viem wallet client (signed by agent key)
 * @param {object} opts.account — viem account (agent wallet)
 * @param {string} opts.vaultAddress — the StrategyVault address
 * @param {object} opts.abis — { STRATEGY_VAULT_ABI, MARGIN_MANAGER_ABI, ORACLE_AGGREGATOR_ABI }
 * @param {string} opts.marginManager — MarginManager address
 * @param {string} opts.oracleAggregator — OracleAggregator address
 * @param {boolean} opts.dryRun — if true, compute but don't send
 * @returns {{ rebalanced: boolean, reason: string }}
 */
async function runRebalanceCycle(opts) {
  const {
    publicClient,
    walletClient,
    account,
    vaultAddress,
    abis,
    marginManager,
    oracleAggregator,
    dryRun,
  } = opts;

  const ctx = `vault:${vaultAddress.slice(0, 8)}`;

  // --- 1. Safety checks ---
  const [isHalted, drawdownBps, totalAssets] = await Promise.all([
    publicClient.readContract({
      address: vaultAddress,
      abi: abis.STRATEGY_VAULT_ABI,
      functionName: "isHalted",
    }),
    publicClient.readContract({
      address: vaultAddress,
      abi: abis.STRATEGY_VAULT_ABI,
      functionName: "currentDrawdownBps",
    }),
    publicClient.readContract({
      address: vaultAddress,
      abi: abis.STRATEGY_VAULT_ABI,
      functionName: "totalAssets",
    }),
  ]);

  if (isHalted) {
    logger.warn(ctx, "Trading is halted — skipping rebalance", {
      drawdownBps: drawdownBps.toString(),
    });
    return { rebalanced: false, reason: "halted" };
  }

  if (totalAssets === 0n) {
    logger.info(ctx, "Vault has no assets — skipping");
    return { rebalanced: false, reason: "no_assets" };
  }

  // --- 2. Read targets ---
  const targetsJson = await publicClient.readContract({
    address: vaultAddress,
    abi: abis.STRATEGY_VAULT_ABI,
    functionName: "currentTargets",
  });

  const targets = parseTargets(targetsJson);
  if (targets.length === 0) {
    logger.info(ctx, "No targets set — skipping rebalance");
    return { rebalanced: false, reason: "no_targets" };
  }

  logger.debug(ctx, "Read targets", { count: targets.length, targets });

  // --- 3. Read current positions and prices ---
  const positionReads = targets.map((t) =>
    publicClient.readContract({
      address: marginManager,
      abi: abis.MARGIN_MANAGER_ABI,
      functionName: "getPosition",
      args: [vaultAddress, t.market, t.side],
    })
  );
  const priceReads = [
    ...new Set(targets.map((t) => t.market)),
  ].map((market) =>
    publicClient.readContract({
      address: oracleAggregator,
      abi: abis.ORACLE_AGGREGATOR_ABI,
      functionName: "getPrice",
      args: [market],
    })
  );

  const [positions, ...prices] = await Promise.all([
    Promise.all(positionReads),
    ...priceReads,
  ]);

  const priceMap = {};
  [...new Set(targets.map((t) => t.market))].forEach((market, i) => {
    priceMap[market] = prices[i];
  });

  logger.debug(ctx, "Current vault NAV", {
    totalAssets: formatUSD(totalAssets),
  });

  // --- 4. Compute drift and build rebalance actions ---
  const actions = [];

  for (let i = 0; i < targets.length; i++) {
    const target = targets[i];
    const position = positions[i];
    const currentSize = position.size;
    const targetSize = (totalAssets * BigInt(target.targetWeightBps)) / BPS;
    const driftBps = computeDriftBps(currentSize, targetSize, totalAssets);

    logger.debug(ctx, "Position drift check", {
      market: target.market,
      side: target.side === SIDE_LONG ? "LONG" : "SHORT",
      currentSize: formatUSD(currentSize),
      targetSize: formatUSD(targetSize),
      driftBps: driftBps.toString(),
      threshold: MIN_DRIFT_BPS.toString(),
    });

    if (driftBps < MIN_DRIFT_BPS) {
      logger.debug(ctx, "Drift below threshold — no action needed", {
        market: target.market,
      });
      continue;
    }

    const price = priceMap[target.market];

    if (targetSize === 0n && currentSize > 0n) {
      // Target is zero — close the position entirely
      actions.push({
        type: "close",
        market: target.market,
        side: target.side,
        reason: `Target weight is 0% — closing position. Current size: ${formatUSD(currentSize)}.`,
      });
   } else if (currentSize < targetSize) {
      const delta = targetSize - currentSize;
      const POSITION_FEE_BPS = 10n;
      const fee = (delta * POSITION_FEE_BPS) / 10000n;
      const collateralDelta = delta - fee;
      actions.push({
        type: "increase",
        market: target.market,
        side: target.side,
        sizeDelta: delta,
        collateralDelta,
        reason: `Rebalancing: position ${formatUSD(currentSize)} is ${Number(driftBps)}bps below target ${formatUSD(targetSize)} (${target.targetWeightBps / 100}% of NAV). Current price: ${formatUSD(price)}. Increasing by ${formatUSD(delta)}.`,
      });
    } else {
      // Position is too large — decrease it
      const delta = currentSize - targetSize;
      actions.push({
        type: "decrease",
        market: target.market,
        side: target.side,
        sizeDelta: delta,
        reason: `Rebalancing: position ${formatUSD(currentSize)} is ${Number(driftBps)}bps above target ${formatUSD(targetSize)} (${target.targetWeightBps / 100}% of NAV). Current price: ${formatUSD(price)}. Decreasing by ${formatUSD(delta)}.`,
      });
    }
  }

  if (actions.length === 0) {
    logger.info(ctx, "All positions within drift threshold — no rebalance needed");
    return { rebalanced: false, reason: "within_threshold" };
  }

  logger.info(ctx, `Rebalance needed — ${actions.length} action(s)`, {
    actions: actions.map((a) => ({
      type: a.type,
      market: a.market,
      side: a.side,
    })),
  });

  if (dryRun) {
    logger.info(ctx, "DRY RUN — would have executed:", {
      actions: actions.map((a) => ({ type: a.type, reason: a.reason })),
    });
    return { rebalanced: false, reason: "dry_run" };
  }

  // --- 5. Execute actions ---
  for (const action of actions) {
    try {
      let hash;
      if (action.type === "close") {
        hash = await walletClient.writeContract({
          address: vaultAddress,
          abi: abis.STRATEGY_VAULT_ABI,
          functionName: "closePosition",
          args: [action.market, action.side, action.reason],
          account,
        });
      } else if (action.type === "increase") {
        hash = await walletClient.writeContract({
          address: vaultAddress,
          abi: abis.STRATEGY_VAULT_ABI,
          functionName: "openPosition",
          args: [
            action.market,
            action.side,
            action.sizeDelta,
            action.collateralDelta,
            action.reason,
          ],
          account,
        });
      } else if (action.type === "decrease") {
        hash = await walletClient.writeContract({
          address: vaultAddress,
          abi: abis.STRATEGY_VAULT_ABI,
          functionName: "decreasePosition",
          args: [
            action.market,
            action.side,
            action.sizeDelta,
            action.reason,
          ],
          account,
        });
      }

      logger.info(ctx, `Executed ${action.type}`, {
        market: action.market,
        side: action.side,
        hash,
      });

      // Wait for the transaction to be included before sending the next one.
      // Sending two trades in the same block risks nonce conflicts.
      await publicClient.waitForTransactionReceipt({ hash, timeout: 60_000 });

    } catch (err) {
      logger.error(ctx, `Action failed: ${action.type}`, {
        error: err.message,
        action,
      });
      // Continue to next action rather than halting the entire cycle —
      // a failed decrease shouldn't block a separate close action.
    }
  }

  return { rebalanced: true, reason: "rebalanced" };
}

module.exports = { runRebalanceCycle, parseTargets };