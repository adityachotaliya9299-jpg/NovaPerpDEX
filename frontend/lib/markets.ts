
export interface MarketInfo {
  /** keccak256(name) as bytes32 — must match the on-chain registered market id exactly. */
  id: `0x${string}`;
  /** Display symbol, e.g. "ETH-USD" */
  symbol: string;
  /** Short label for compact UI, e.g. "ETH" */
  label: string;
  /** Full asset name for tooltips/secondary text. */
  name: string;
  /** Decimal places typically shown for this asset's price (BTC needs fewer trailing digits at scale). */
  priceDecimals: number;
}

export const MARKETS: MarketInfo[] = [
  {
    id: "0x2430f68ea2e8d4151992bb7fc3a4c472087a6149bf7e0232704396162ab7c1f7",
    symbol: "ETH-USD",
    label: "ETH",
    name: "Ethereum",
    priceDecimals: 2,
  },
  {
    id: "0xb39c402b9bd8428ba7a4cc2d1aca1432756cddeb60941a9175541a819095269e",
    symbol: "BTC-USD",
    label: "BTC",
    name: "Bitcoin",
    priceDecimals: 2,
  },
];

export const DEFAULT_MARKET = MARKETS[0];

export function getMarketById(id: string): MarketInfo {
  return MARKETS.find((m) => m.id.toLowerCase() === id.toLowerCase()) ?? DEFAULT_MARKET;
}

/**
 * CoinGecko coin id for chart history — separate from the on-chain market
 * id since CoinGecko uses its own naming scheme (e.g. "bitcoin", not
 * "BTC-USD"). Used by PriceChart.tsx.
 */
export function coingeckoId(symbol: string): string {
  if (symbol === "BTC-USD") return "bitcoin";
  return "ethereum";
}