/**
 * Qevora Agent Runner
 *
 * Entry point for the autonomous trading agent. Runs on a fixed cron
 * schedule, discovers all active strategies via StrategyRegistry,
 * and runs one rebalance cycle per strategy.
 *
 * Phase C will add the LLM thesis parser here — for now, targets must be
 * set manually via StrategyVault.setCurrentTargets() before the agent
 * will trade. This is intentional: you should verify the rebalancer works
 * correctly with known, manually-set targets before letting an LLM write them.
 */

require("dotenv").config();
const cron = require("node-cron");

const logger = require("./lib/logger");
const { createClients, STRATEGY_VAULT_ABI, MARGIN_MANAGER_ABI, ORACLE_AGGREGATOR_ABI, STRATEGY_REGISTRY_ABI } = require("./lib/contracts");
const { runRebalanceCycle } = require("./lib/rebalancer");
const stateManager = require("./lib/state");

const INTERVAL_SEC = parseInt(process.env.REBALANCE_INTERVAL_SEC ?? "300", 10);
const MAX_GAS_GWEI = BigInt(process.env.MAX_GAS_GWEI ?? "50") * BigInt(1e9);
const DRY_RUN = process.env.DRY_RUN === "true";

const STRATEGY_REGISTRY = process.env.STRATEGY_REGISTRY;
const MARGIN_MANAGER = process.env.MARGIN_MANAGER;
const ORACLE_AGGREGATOR = process.env.ORACLE_AGGREGATOR;

const abis = { STRATEGY_VAULT_ABI, MARGIN_MANAGER_ABI, ORACLE_AGGREGATOR_ABI };

const REQUIRED = [
  "AGENT_PRIVATE_KEY",
  "RPC_URL",
  "STRATEGY_REGISTRY",
  "MARGIN_MANAGER",
  "ORACLE_AGGREGATOR",
  "ETH_USD_MARKET",
  "BTC_USD_MARKET",
];
for (const key of REQUIRED) {
  if (!process.env[key]) {
    console.error(`[FATAL] Missing required env var: ${key}`);
    process.exit(1);
  }
}

// ------------------------------------------------------------------ //

async function checkGasPrice(publicClient) {
  const gasPrice = await publicClient.getGasPrice();
  if (gasPrice > MAX_GAS_GWEI) {
    logger.warn("runner", "Gas price above limit — skipping cycle", {
      gasPrice: (Number(gasPrice) / 1e9).toFixed(2) + " gwei",
      limit: process.env.MAX_GAS_GWEI + " gwei",
    });
    return false;
  }
  return true;
}

async function discoverVaults(publicClient) {
  try {
    const result = await publicClient.readContract({
      address: STRATEGY_REGISTRY,
      abi: STRATEGY_REGISTRY_ABI,
      functionName: "getActiveStrategies",
      args: [0n, 50n],
    });
    const [strategies] = result;
    return strategies.map((s) => s.vault.toLowerCase());
  } catch (err) {
    logger.error("runner", "Failed to discover vaults from registry", {
      error: err.message,
    });
    return [];
  }
}

async function verifyAgentWallet(publicClient, vaultAddress, agentAddress) {
  try {
    const configuredAgent = await publicClient.readContract({
      address: vaultAddress,
      abi: STRATEGY_VAULT_ABI,
      functionName: "agentWallet",
    });
    if (configuredAgent.toLowerCase() !== agentAddress.toLowerCase()) {
      logger.warn("runner", "Agent wallet mismatch — skipping vault", {
        vault: vaultAddress,
        configured: configuredAgent,
        ours: agentAddress,
      });
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

async function runCycle() {
  const { publicClient, walletClient, account } = createClients();
  const state = stateManager.load();

  logger.info("runner", `Starting rebalance cycle`, {
    dryRun: DRY_RUN,
    agentWallet: account.address,
  });

  // Gas price check — skip the entire cycle if gas is too high
  const gasOk = await checkGasPrice(publicClient);
  if (!gasOk) return;

  // Discover all active vaults from the registry
  const vaults = await discoverVaults(publicClient);
  logger.info("runner", `Discovered ${vaults.length} active vault(s)`, {
    vaults,
  });

  for (const vaultAddress of vaults) {
    const vaultState = stateManager.getVaultState(state, vaultAddress);
    vaultState.cycleCount += 1;

    // Verify this agent wallet is the authorized agent for this vault
    const authorized = await verifyAgentWallet(
      publicClient,
      vaultAddress,
      account.address
    );
    if (!authorized) continue;

    try {
      const result = await runRebalanceCycle({
        publicClient,
        walletClient,
        account,
        vaultAddress,
        abis,
        marginManager: MARGIN_MANAGER,
        oracleAggregator: ORACLE_AGGREGATOR,
        dryRun: DRY_RUN,
      });

      if (result.rebalanced) {
        vaultState.lastRebalanceAt = Math.floor(Date.now() / 1000);
      }
      vaultState.lastError = null;

      logger.info("runner", `Cycle complete for vault`, {
        vault: vaultAddress,
        result: result.reason,
        cycleCount: vaultState.cycleCount,
      });
    } catch (err) {
      vaultState.lastError = err.message;
      logger.error("runner", `Unhandled error in rebalance cycle`, {
        vault: vaultAddress,
        error: err.message,
        stack: err.stack,
      });
    }
  }

  stateManager.save(state);
  logger.info("runner", "Cycle complete — state saved");
}

// ------------------------------------------------------------------ //
//                           Main entry                               //
// ------------------------------------------------------------------ //

logger.info("runner", "Qevora Agent Runner starting", {
  interval: INTERVAL_SEC + "s",
  dryRun: DRY_RUN,
  registry: STRATEGY_REGISTRY,
});

if (DRY_RUN) {
  logger.warn("runner", "DRY RUN MODE — no transactions will be sent");
}

// Run once immediately on startup, then on the cron schedule
runCycle().catch((err) => {
  logger.error("runner", "Fatal error on first cycle", { error: err.message });
});

// Convert seconds to a cron expression
// e.g. 300 seconds = every 5 minutes = "*/5 * * * *"
const minutes = Math.max(1, Math.round(INTERVAL_SEC / 60));
const cronExpr = `*/${minutes} * * * *`;
logger.info("runner", `Scheduling cron: ${cronExpr}`);

cron.schedule(cronExpr, () => {
  runCycle().catch((err) => {
    logger.error("runner", "Fatal error in scheduled cycle", {
      error: err.message,
    });
  });
});

// Graceful shutdown
process.on("SIGTERM", () => {
  logger.info("runner", "SIGTERM received — shutting down gracefully");
  process.exit(0);
});
process.on("SIGINT", () => {
  logger.info("runner", "SIGINT received — shutting down");
  process.exit(0);
});