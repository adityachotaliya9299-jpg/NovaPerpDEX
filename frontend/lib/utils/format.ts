/**
 * Formatting utilities for NovaPerpDEX.
 * All on-chain values are WAD-scaled (1e18). These helpers convert to
 * human-readable strings for display, keeping a monospace font context in
 * mind: consistent decimal widths prevent layout shift as values update.
 */

const WAD = BigInt("1000000000000000000"); // 1e18

/** Converts a WAD bigint to a plain JS number (loses precision beyond ~15 sig figs). */
export function wadToNumber(wad: bigint): number {
  return Number(wad) / 1e18;
}

/** Formats a WAD bigint as a USD price string, e.g. "$2,000.00" */
export function formatPrice(wad: bigint): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(wadToNumber(wad));
}

/** Formats a WAD bigint as a plain number with `decimals` decimal places. */
export function formatAmount(wad: bigint, decimals = 2): string {
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(wadToNumber(wad));
}

/** Formats a PnL number with sign, returning the text and a Tailwind color class. */
export function formatPnl(pnl: number): { text: string; colorClass: string } {
  const formatted = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Math.abs(pnl));
  return {
    text: `${pnl >= 0 ? "+" : "-"}${formatted}`,
    colorClass: pnl >= 0 ? "text-accent-long" : "text-accent-short",
  };
}

/** Formats a WAD leverage value (e.g. 10e18 = 10x) as "10.0x". */
export function formatLeverage(wad: bigint): string {
  return `${wadToNumber(wad).toFixed(1)}x`;
}

/**
 * Computes unrealized PnL from position fields (all WAD bigints).
 * Returns a plain number in collateral units (nUSD).
 */
export function computePnl(
  size: bigint,
  entryPrice: bigint,
  currentPrice: bigint,
  isLong: boolean
): number {
  if (size === 0n || entryPrice === 0n) return 0;
  const sizeFl = wadToNumber(size);
  const entryFl = wadToNumber(entryPrice);
  const currFl = wadToNumber(currentPrice);
  const priceDelta = currFl - entryFl;
  return isLong
    ? sizeFl * (priceDelta / entryFl)
    : sizeFl * (-priceDelta / entryFl);
}

/**
 * Estimates the liquidation price for a position.
 * maintenanceMarginBps: e.g. 200 = 2%.
 * Returns the liquidation price as a plain number.
 */
export function estimateLiqPrice(
  size: bigint,
  collateral: bigint,
  entryPrice: bigint,
  maintenanceMarginBps: number,
  isLong: boolean
): number {
  if (size === 0n || entryPrice === 0n) return 0;
  const sizeFl = wadToNumber(size);
  const collFl = wadToNumber(collateral);
  const entryFl = wadToNumber(entryPrice);
  const mm = maintenanceMarginBps / 10000;
  // Solve equity = maintenance margin for price:
  // Long:  collateral + size*(p/entry - 1) = size*mm  =>  p = entry*(1 + (size*mm - collateral)/size)
  // Short: collateral - size*(p/entry - 1) = size*mm  =>  p = entry*(1 - (size*mm - collateral)/size)
  return isLong
    ? entryFl * (1 + (sizeFl * mm - collFl) / sizeFl)
    : entryFl * (1 - (sizeFl * mm - collFl) / sizeFl);
}

/**
 * Computes position health as a 0–1 float.
 * 1.0 = fully healthy, 0.0 = at liquidation threshold.
 * Used to drive the gradient health bar width and color.
 */
export function computeHealth(
  equity: number,
  size: bigint,
  maintenanceMarginBps: number
): number {
  if (size === 0n) return 1;
  const sizeFl = wadToNumber(size);
  const maintenanceEquity = sizeFl * (maintenanceMarginBps / 10000);
  // Health = how far above maintenance equity we are, relative to 10x that floor
  return Math.max(0, Math.min(1, equity / (maintenanceEquity * 10)));
}

/**
 * Formats a WAD-per-second funding rate as an annualised percentage string.
 * e.g. 1e12 per second → tiny fraction of a % per year.
 */
export function formatFundingRate(ratePerSecond: bigint): string {
  const ratePerYear = wadToNumber(ratePerSecond) * 365 * 24 * 3600 * 100;
  const sign = ratePerYear >= 0 ? "+" : "";
  return `${sign}${ratePerYear.toFixed(4)}%/yr`;
}

/**
 * Parses a user-typed decimal string into a WAD bigint.
 * Returns 0n on empty or invalid input — never throws.
 */
export function parseWad(value: string): bigint {
  try {
    const trimmed = value.trim();
    if (!trimmed || isNaN(Number(trimmed))) return 0n;
    const [whole, frac = ""] = trimmed.split(".");
    // Pad/truncate fractional part to exactly 18 digits
    const fracPadded = frac.slice(0, 18).padEnd(18, "0");
    return BigInt(whole) * WAD + BigInt(fracPadded);
  } catch {
    return 0n;
  }
}

/**
 * Side enum matching Solidity's DataTypes.Side.
 * LONG = 0, SHORT = 1 — confirmed from src/libraries/DataTypes.sol.
 */
export const SIDE = { LONG: 0, SHORT: 1 } as const;
export type Side = (typeof SIDE)[keyof typeof SIDE];