/**
 * Contract ABIs and client setup for the agent runner.
 * Uses viem for all on-chain reads and writes.
 */

const { createPublicClient, createWalletClient, http } = require("viem");
const { privateKeyToAccount } = require("viem/accounts");
const { sepolia } = require("viem/chains");

const STRATEGY_VAULT_ABI = [
  {
    name: "totalAssets",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "sharePrice",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "currentDrawdownBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "isHalted",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "bool" }],
  },
  {
    name: "currentTargets",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
  {
    name: "maxDrawdownBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "maxSinglePositionBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "agentWallet",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  // Writes
  {
    name: "openPosition",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "market", type: "bytes32" },
      { name: "side", type: "uint8" },
      { name: "sizeDelta", type: "uint256" },
      { name: "collateralDelta", type: "uint256" },
      { name: "reason", type: "string" },
    ],
    outputs: [],
  },
  {
    name: "closePosition",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "market", type: "bytes32" },
      { name: "side", type: "uint8" },
      { name: "reason", type: "string" },
    ],
    outputs: [],
  },
  {
    name: "decreasePosition",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "market", type: "bytes32" },
      { name: "side", type: "uint8" },
      { name: "sizeDelta", type: "uint256" },
      { name: "reason", type: "string" },
    ],
    outputs: [],
  },
  {
    name: "setCurrentTargets",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "targets", type: "string" }],
    outputs: [],
  },
];

const MARGIN_MANAGER_ABI = [
  {
    name: "getPosition",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "account", type: "address" },
      { name: "market", type: "bytes32" },
      { name: "side", type: "uint8" },
    ],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "owner", type: "address" },
          { name: "market", type: "bytes32" },
          { name: "side", type: "uint8" },
          { name: "size", type: "uint256" },
          { name: "collateral", type: "uint256" },
          { name: "entryPrice", type: "uint256" },
          { name: "entryFundingIndex", type: "int256" },
          { name: "lastIncreasedAt", type: "uint64" },
          { name: "status", type: "uint8" },
        ],
      },
    ],
  },
  {
    name: "longOpenInterest",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "market", type: "bytes32" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "shortOpenInterest",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "market", type: "bytes32" }],
    outputs: [{ type: "uint256" }],
  },
];

const ORACLE_AGGREGATOR_ABI = [
  {
    name: "getPrice",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "market", type: "bytes32" }],
    outputs: [{ type: "uint256" }],
  },
];

const STRATEGY_REGISTRY_ABI = [
  {
    name: "totalStrategies",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "getActiveStrategies",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "offset", type: "uint256" },
      { name: "limit", type: "uint256" },
    ],
    outputs: [
      {
        name: "result",
        type: "tuple[]",
        components: [
          { name: "vault", type: "address" },
          { name: "creator", type: "address" },
          { name: "name", type: "string" },
          { name: "thesis", type: "string" },
          { name: "registeredAt", type: "uint256" },
          { name: "active", type: "bool" },
        ],
      },
      { name: "total", type: "uint256" },
    ],
  },
];

const VAULT_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "totalOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
];

function createClients() {
  const account = privateKeyToAccount(process.env.AGENT_PRIVATE_KEY);

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(process.env.RPC_URL),
  });

  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http(process.env.RPC_URL),
  });

  return { publicClient, walletClient, account };
}

module.exports = {
  STRATEGY_VAULT_ABI,
  MARGIN_MANAGER_ABI,
  ORACLE_AGGREGATOR_ABI,
  STRATEGY_REGISTRY_ABI,
  VAULT_ABI,
  createClients,
};