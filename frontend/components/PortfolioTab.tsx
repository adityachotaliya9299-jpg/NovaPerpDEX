"use client";

import { useAccount, useReadContracts } from "wagmi";
import { contracts } from "@/lib/contracts";
import { MARKETS, type MarketInfo } from "@/lib/markets";
import {
  formatAmount,
  formatPnl,
  computePnl,
  computeHealth,
  wadToNumber,
  SIDE,
} from "@/lib/utils/format";

const MAINTENANCE_BPS = 200;

interface RawPosition {
  size: bigint;
  collateral: bigint;
  entryPrice: bigint;
  side: number;
}

function StatCard({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>
        {label}
      </div>
      <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: accent ?? "var(--text-primary)" }}>
        {value}
      </div>
    </div>
  );
}

export function PortfolioTab() {
  const { address } = useAccount();

  const positionCalls = MARKETS.flatMap((m) => [
    { ...contracts.marginManager, functionName: "getPosition", args: [address ?? "0x0000000000000000000000000000000000000000", m.id, SIDE.LONG] },
    { ...contracts.marginManager, functionName: "getPosition", args: [address ?? "0x0000000000000000000000000000000000000000", m.id, SIDE.SHORT] },
  ]);
  const priceCalls = MARKETS.map((m) => ({
    ...contracts.priceFeed,
    functionName: "getPrice",
    args: [m.id],
  }));

  const { data } = useReadContracts({
    contracts: [
      ...positionCalls,
      ...priceCalls,
      { ...contracts.lpVault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.lpVault, functionName: "sharePrice" },
      { ...contracts.rewardDistributor, functionName: "stakedOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.rewardDistributor, functionName: "earned", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.collateralToken, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
    ],
    query: { enabled: !!address, refetchInterval: 12_000 },
  });

  if (!address) {
    return (
      <div className="border p-12 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm" style={{ color: "var(--text-muted)" }}>
          Connect your wallet to view your portfolio.
        </p>
      </div>
    );
  }

  const tailStart = positionCalls.length + priceCalls.length;
  const lpShares = (data?.[tailStart]?.result as bigint | undefined) ?? 0n;
  const sharePrice = (data?.[tailStart + 1]?.result as bigint | undefined) ?? 0n;
  const stakedShares = (data?.[tailStart + 2]?.result as bigint | undefined) ?? 0n;
  const earned = (data?.[tailStart + 3]?.result as bigint | undefined) ?? 0n;
  const walletBalance = (data?.[tailStart + 4]?.result as bigint | undefined) ?? 0n;

  // Aggregate PnL and gather per-market position rows across every
  // registered market — a portfolio view that only showed ETH would be
  // actively misleading once BTC positions exist.
  const rows: { market: MarketInfo; label: string; position: RawPosition; currentPrice: bigint; accent: string }[] = [];
  let totalTradingPnl = 0;

  MARKETS.forEach((market, i) => {
    const longPos = data?.[i * 2]?.result as RawPosition | undefined;
    const shortPos = data?.[i * 2 + 1]?.result as RawPosition | undefined;
    const currentPrice = (data?.[positionCalls.length + i]?.result as bigint | undefined) ?? 0n;

    if (longPos && longPos.size > 0n) {
      const pnl = computePnl(longPos.size, longPos.entryPrice, currentPrice, true);
      totalTradingPnl += pnl;
      rows.push({ market, label: "LONG", position: longPos, currentPrice, accent: "var(--accent-long)" });
    }
    if (shortPos && shortPos.size > 0n) {
      const pnl = computePnl(shortPos.size, shortPos.entryPrice, currentPrice, false);
      totalTradingPnl += pnl;
      rows.push({ market, label: "SHORT", position: shortPos, currentPrice, accent: "var(--accent-short)" });
    }
  });

  const totalLpShares = lpShares + stakedShares;
  const lpValueUsd = wadToNumber(totalLpShares) * wadToNumber(sharePrice);

  const netWorth = wadToNumber(walletBalance) + lpValueUsd + totalTradingPnl;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Wallet (nUSD)" value={`$${formatAmount(walletBalance)}`} />
        <StatCard label="LP position value" value={`$${lpValueUsd.toFixed(2)}`} accent="var(--accent-info)" />
        <StatCard
          label="Trading PnL (unrealized, all markets)"
          value={formatPnl(totalTradingPnl).text}
          accent={totalTradingPnl >= 0 ? "var(--accent-long)" : "var(--accent-short)"}
        />
        <StatCard label="Unclaimed rewards" value={`${formatAmount(earned, 4)} nRWD`} accent="var(--accent-long)" />
      </div>

      <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
          Estimated net worth
        </div>
        <div className="font-mono text-2xl font-semibold tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${netWorth.toFixed(2)}
        </div>
        <p className="text-[11px] mt-1" style={{ color: "var(--text-muted)" }}>
          Wallet nUSD + LP position value + unrealized trading PnL across all
          markets. Doesn&apos;t include unclaimed staking rewards (different
          token) or gas costs.
        </p>
      </div>

      {rows.length > 0 && (
        <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
            <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
              Open Positions — All Markets
            </span>
          </div>
          {rows.map((r, i) => (
            <PortfolioPositionRow
              key={`${r.market.id}-${r.label}-${i}`}
              label={r.label}
              market={r.market}
              position={r.position}
              currentPrice={r.currentPrice}
              accentColor={r.accent}
            />
          ))}
        </div>
      )}

      {totalLpShares > 0n && (
        <div className="border p-4 flex items-center justify-between" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div>
            <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
              LP shares ({formatAmount(lpShares, 4)} held + {formatAmount(stakedShares, 4)} staked)
            </div>
            <div className="font-mono text-sm tabular-nums" style={{ color: "var(--text-primary)" }}>
              {formatAmount(totalLpShares, 6)} shares total
            </div>
          </div>
          <div className="text-right">
            <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
              Share price
            </div>
            <div className="font-mono text-sm tabular-nums" style={{ color: "var(--accent-info)" }}>
              ${formatAmount(sharePrice, 4)}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function PortfolioPositionRow({
  label,
  market,
  position,
  currentPrice,
  accentColor,
}: {
  label: string;
  market: MarketInfo;
  position: RawPosition;
  currentPrice: bigint;
  accentColor: string;
}) {
  const isLong = position.side === SIDE.LONG;
  const pnl = computePnl(position.size, position.entryPrice, currentPrice, isLong);
  const { text: pnlText, colorClass: pnlColor } = formatPnl(pnl);
  const equity = wadToNumber(position.collateral) + pnl;
  const health = computeHealth(equity, position.size, MAINTENANCE_BPS);

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span className="font-semibold px-1.5 py-0.5" style={{ background: `${accentColor}22`, color: accentColor }}>
          {label}
        </span>
        <span style={{ color: "var(--text-muted)" }}>{market.symbol}</span>
        <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${formatAmount(position.size)}
        </span>
      </div>
      <div className="flex items-center gap-3">
        <span className={`font-mono text-xs tabular-nums font-semibold ${pnlColor}`}>{pnlText}</span>
        <span className="text-[10px] font-mono tabular-nums" style={{ color: health > 0.5 ? "var(--accent-long)" : health > 0.25 ? "var(--accent-warn)" : "var(--accent-short)" }}>
          {(health * 100).toFixed(0)}% health
        </span>
      </div>
    </div>
  );
}