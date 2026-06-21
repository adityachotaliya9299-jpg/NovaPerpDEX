/**
 * A thin GraphQL client for the NovaPerpDEX subgraph.
 *
 * No GraphQL library dependency needed for simple queries like these — a
 * plain fetch() POST to the Studio query endpoint is sufficient and avoids
 * pulling in urql/apollo for what's currently a handful of read-only
 * queries. If query complexity grows significantly (e.g. live subscriptions
 * via The Graph's websocket support), revisit with a proper client then.
 */

const SUBGRAPH_URL =
  process.env.NEXT_PUBLIC_SUBGRAPH_URL ??
  "https://api.studio.thegraph.com/query/1755484/novaperpdex/v0.1.0";

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

// ---- Orders (11.2) ----

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

// ---- Position & trade history (11.3) ----

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