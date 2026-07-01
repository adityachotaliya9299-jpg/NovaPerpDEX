
const SUBGRAPH_URL =
  process.env.NEXT_PUBLIC_SUBGRAPH_URL ??
  "https://api.studio.thegraph.com/query/1755484/novaperpdex/v0.3.0";
async function querySubgraph<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const res = await fetch(SUBGRAPH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) {
    throw new Error(`Subgraph request failed: ${res.status}`);
  }
  const json = await res.json();
  if (json.errors) {
    throw new Error(`Subgraph query error: ${json.errors[0]?.message ?? "unknown"}`);
  }
  return json.data as T;
}

// ---- Orders 

export interface SubgraphOrder {
  id: string;
  account: string;
  market: string;
  status: "PLACED" | "EXECUTED" | "CANCELLED";
  placedAt: string;
  placedTxHash: string;
  executedAt: string | null;
  executedPrice: string | null;
  executedTxHash: string | null;
  cancelledAt: string | null;
  cancelledTxHash: string | null;
}

const ORDERS_QUERY = `
  query Orders($status: String) {
    orders(
      first: 200
      orderBy: placedAt
      orderDirection: desc
      where: { status: $status }
    ) {
      id
      account
      market
      status
      placedAt
      placedTxHash
      executedAt
      executedPrice
      executedTxHash
      cancelledAt
      cancelledTxHash
    }
  }
`;

export async function fetchActiveOrders(): Promise<SubgraphOrder[]> {
  const data = await querySubgraph<{ orders: SubgraphOrder[] }>(ORDERS_QUERY, {
    status: "PLACED",
  });
  return data.orders;
}

// ---- Position & trade history 

export interface SubgraphPositionEvent {
  id: string;
  key: string;
  account: string;
  market: string;
  kind: "INCREASE" | "DECREASE";
  side: number | null;
  sizeDelta: string;
  collateralDelta: string | null;
  realizedPnl: string | null;
  price: string;
  timestamp: string;
  txHash: string;
}

export interface SubgraphLiquidation {
  id: string;
  account: string;
  market: string;
  side: number;
  keeper: string;
  size: string;
  pnl: string;
  price: string;
  timestamp: string;
  txHash: string;
}

const HISTORY_QUERY = `
  query History($account: Bytes!) {
    positionEvents(
      first: 100
      orderBy: timestamp
      orderDirection: desc
      where: { account: $account }
    ) {
      id
      key
      account
      market
      kind
      side
      sizeDelta
      collateralDelta
      realizedPnl
      price
      timestamp
      txHash
    }
    liquidationEvents(
      first: 50
      orderBy: timestamp
      orderDirection: desc
      where: { account: $account }
    ) {
      id
      account
      market
      side
      keeper
      size
      pnl
      price
      timestamp
      txHash
    }
  }
`;

export async function fetchAccountHistory(account: string): Promise<{
  events: SubgraphPositionEvent[];
  liquidations: SubgraphLiquidation[];
}> {
  const data = await querySubgraph<{
    positionEvents: SubgraphPositionEvent[];
    liquidationEvents: SubgraphLiquidation[];
  }>(HISTORY_QUERY, { account: account.toLowerCase() });
  return { events: data.positionEvents, liquidations: data.liquidationEvents };
}


export interface SubgraphPosition {
  id: string;
  account: string;
  market: string;
  side: number;
  size: string;
  collateral: string;
  entryPrice: string;
  status: string;
  openedAt: string;
  lastUpdatedAt: string;
}

const LARGEST_POSITIONS_QUERY = `
  query LargestPositions {
    positions(
      first: 10
      orderBy: size
      orderDirection: desc
      where: { status: "OPEN" }
    ) {
      id
      account
      market
      side
      size
      collateral
      entryPrice
      status
      openedAt
      lastUpdatedAt
    }
  }
`;

export async function fetchLargestPositions(): Promise<SubgraphPosition[]> {
  const data = await querySubgraph<{ positions: SubgraphPosition[] }>(LARGEST_POSITIONS_QUERY);
  return data.positions;
}

const RECENT_LIQUIDATIONS_QUERY = `
  query RecentLiquidations {
    liquidationEvents(first: 10, orderBy: timestamp, orderDirection: desc) {
      id
      account
      market
      side
      keeper
      size
      pnl
      price
      timestamp
      txHash
    }
  }
`;

export async function fetchRecentLiquidations(): Promise<SubgraphLiquidation[]> {
  const data = await querySubgraph<{ liquidationEvents: SubgraphLiquidation[] }>(
    RECENT_LIQUIDATIONS_QUERY
  );
  return data.liquidationEvents;
}

export interface SubgraphFundingUpdate {
  id: string;
  market: string;
  cumulativeIndex: string;
  ratePerSecond: string;
  timestamp: string;
}

const FUNDING_HISTORY_QUERY = `
  query FundingHistory($market: Bytes!) {
    fundingUpdates(
      first: 200
      orderBy: timestamp
      orderDirection: desc
      where: { market: $market }
    ) {
      id
      market
      cumulativeIndex
      ratePerSecond
      timestamp
    }
  }
`;

export async function fetchFundingHistory(market: string): Promise<SubgraphFundingUpdate[]> {
  const data = await querySubgraph<{ fundingUpdates: SubgraphFundingUpdate[] }>(
    FUNDING_HISTORY_QUERY,
    { market: market.toLowerCase() }
  );
  return data.fundingUpdates.reverse(); 
}


export interface SubgraphTraderVolume {
  id: string;
  account: string;
  totalVolume: string;
  tradeCount: number;
  lastTradeAt: string;
}

const LEADERBOARD_QUERY = `
  query Leaderboard {
    traderVolumes(
      first: 50
      orderBy: totalVolume
      orderDirection: desc
    ) {
      id
      account
      totalVolume
      tradeCount
      lastTradeAt
    }
  }
`;

export async function fetchLeaderboard(): Promise<SubgraphTraderVolume[]> {
  const url =
    process.env.NEXT_PUBLIC_SUBGRAPH_URL ??
    "https://api.studio.thegraph.com/query/1755484/novaperpdex/v0.3.0";
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query: LEADERBOARD_QUERY }),
  });
  if (!res.ok) throw new Error(`Subgraph request failed: ${res.status}`);
  const json = await res.json();
  if (json.errors) throw new Error(json.errors[0]?.message ?? "unknown");
  return (json.data as { traderVolumes: SubgraphTraderVolume[] }).traderVolumes;
}

// ---- Phase B: Strategy / Agent queries ----

export interface SubgraphStrategy {
  id: string;
  vault: string;
  creator: string;
  agentWallet: string;
  name: string;
  thesis: string;
  maxDrawdownBps: string;
  maxLeverageBps: string;
  maxSinglePositionBps: string;
  createdAt: string;
  active: boolean;
  tradingHalted: boolean;
  totalDeposited: string;
  totalWithdrawn: string;
  investorCount: number;
  tradeCount: number;
  lastTradeAt: string | null;
  peakNAV: string;
  currentDrawdownBpsAtLastUpdate: string;
}

export interface SubgraphStrategyTrade {
  id: string;
  strategy: string;
  market: string;
  side: number;
  sizeDelta: string;
  collateralDelta: string;
  isIncrease: boolean;
  reason: string;
  timestamp: string;
  txHash: string;
}

export interface SubgraphStrategyDeposit {
  id: string;
  strategy: string;
  investor: string;
  assets: string;
  shares: string;
  timestamp: string;
  txHash: string;
}

export interface SubgraphStrategyWithdraw {
  id: string;
  strategy: string;
  investor: string;
  assets: string;
  shares: string;
  timestamp: string;
  txHash: string;
}

export interface SubgraphStrategyPosition {
  id: string;
  strategy: string;
  investor: string;
  sharesHeld: string;
  totalDeposited: string;
  totalWithdrawn: string;
  firstDepositAt: string;
  lastActivityAt: string;
}

const ALL_STRATEGIES_QUERY = `
  query AllStrategies {
    strategies(
      first: 50
      orderBy: createdAt
      orderDirection: desc
      where: { active: true }
    ) {
      id
      vault
      creator
      agentWallet
      name
      thesis
      maxDrawdownBps
      maxLeverageBps
      maxSinglePositionBps
      createdAt
      active
      tradingHalted
      totalDeposited
      totalWithdrawn
      investorCount
      tradeCount
      lastTradeAt
      peakNAV
      currentDrawdownBpsAtLastUpdate
    }
  }
`;

const STRATEGY_DETAIL_QUERY = `
  query StrategyDetail($vault: ID!) {
    strategy(id: $vault) {
      id
      vault
      creator
      agentWallet
      name
      thesis
      maxDrawdownBps
      maxLeverageBps
      maxSinglePositionBps
      createdAt
      active
      tradingHalted
      totalDeposited
      totalWithdrawn
      investorCount
      tradeCount
      lastTradeAt
      peakNAV
      currentDrawdownBpsAtLastUpdate
    }
  }
`;

const STRATEGY_TRADES_QUERY = `
  query StrategyTrades($vault: Bytes!, $first: Int) {
    strategyTrades(
      first: $first
      orderBy: timestamp
      orderDirection: desc
      where: { strategy: $vault }
    ) {
      id
      strategy
      market
      side
      sizeDelta
      collateralDelta
      isIncrease
      reason
      timestamp
      txHash
    }
  }
`;

const INVESTOR_POSITIONS_QUERY = `
  query InvestorPositions($investor: Bytes!) {
    strategyPositions(
      first: 50
      where: { investor: $investor, sharesHeld_gt: "0" }
    ) {
      id
      strategy
      investor
      sharesHeld
      totalDeposited
      totalWithdrawn
      firstDepositAt
      lastActivityAt
    }
  }
`;

export async function fetchAllStrategies(): Promise<SubgraphStrategy[]> {
  const data = await querySubgraph<{ strategies: SubgraphStrategy[] }>(
    ALL_STRATEGIES_QUERY
  );
  return data.strategies;
}

export async function fetchStrategyDetail(
  vault: string
): Promise<SubgraphStrategy | null> {
  const data = await querySubgraph<{ strategy: SubgraphStrategy | null }>(
    STRATEGY_DETAIL_QUERY,
    { vault: vault.toLowerCase() }
  );
  return data.strategy;
}

export async function fetchStrategyTrades(
  vault: string,
  first: number = 50
): Promise<SubgraphStrategyTrade[]> {
  const data = await querySubgraph<{ strategyTrades: SubgraphStrategyTrade[] }>(
    STRATEGY_TRADES_QUERY,
    { vault: vault.toLowerCase(), first }
  );
  return data.strategyTrades;
}

export async function fetchInvestorPositions(
  investor: string
): Promise<SubgraphStrategyPosition[]> {
  const data = await querySubgraph<{
    strategyPositions: SubgraphStrategyPosition[];
  }>(INVESTOR_POSITIONS_QUERY, { investor: investor.toLowerCase() });
  return data.strategyPositions;
}