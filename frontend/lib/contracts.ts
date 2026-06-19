import anvilDeployment from "./deployments/31337.json";
import sepoliaDeployment from "./deployments/11155111.json";
import {
  MarginManagerAbi,
  PriceFeedAbi,
  VaultAbi,
  CollateralVaultAbi,
  LeverageControllerAbi,
  FundingRateEngineAbi,
  RiskManagerAbi,
  OrderBookAbi,
  StopLossManagerAbi,
  LPVaultAbi,
  RewardDistributorAbi,
  LiquidationEngineAbi,
  PositionRouterAbi,
  MockERC20Abi,
} from "./abis";


const ACTIVE_CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");

const deployment = ACTIVE_CHAIN_ID === 11155111 ? sepoliaDeployment : anvilDeployment;

/** keccak256("ETH-USD") — the only market wired up in Deploy.s.sol. */
export const ETH_USD_MARKET = deployment.ETH_USD as `0x${string}`;

function addr(key: keyof typeof deployment): `0x${string}` {
  return deployment[key] as `0x${string}`;
}

export const contracts = {
  marginManager: { address: addr("MarginManager"), abi: MarginManagerAbi },
  priceFeed: { address: addr("PriceFeed"), abi: PriceFeedAbi },
  vault: { address: addr("Vault"), abi: VaultAbi },
  collateralVault: { address: addr("CollateralVault"), abi: CollateralVaultAbi },
  leverageController: { address: addr("LeverageController"), abi: LeverageControllerAbi },
  fundingRateEngine: { address: addr("FundingRateEngine"), abi: FundingRateEngineAbi },
  riskManager: { address: addr("RiskManager"), abi: RiskManagerAbi },
  orderBook: { address: addr("OrderBook"), abi: OrderBookAbi },
  stopLossManager: { address: addr("StopLossManager"), abi: StopLossManagerAbi },
  lpVault: { address: addr("LPVault"), abi: LPVaultAbi },
  rewardDistributor: { address: addr("RewardDistributor"), abi: RewardDistributorAbi },
  liquidationEngine: { address: addr("LiquidationEngine"), abi: LiquidationEngineAbi },
  positionRouter: { address: addr("PositionRouter"), abi: PositionRouterAbi },
  collateralToken: { address: addr("MockUSD"), abi: MockERC20Abi },
  rewardToken: { address: addr("RewardToken"), abi: MockERC20Abi },
} as const;

/** True once real (non-zero) addresses are in the active deployment JSON. */
export const isDeployed = contracts.marginManager.address !== "0x0000000000000000000000000000000000000000";