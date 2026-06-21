"use client";

import { useEffect, useState } from "react";
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
import { fetchAccountHistory, type SubgraphPositionEvent } from "@/lib/subgraph";

const MAINTENANCE_BPS = 200;

interface RawPosition {
  size: bigint;
  collateral: bigint;
  entryPrice: bigint;
  side: number;
}

function StatCard({ label, value, accent, sub }: { label: string; value: string; accent?: string; sub?: string }) {
  return (
    <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>{label}</div>
      <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: accent ?? "var(--text-primary)" }}>
        {value}
      </div>
      {sub && <div className="text-[11px] mt-1" style={{ color: "var(--text-muted)" }}>{sub}</div>}
    </div>
  );
}

function EquitySparkline({ events, currentEquity }: { events: SubgraphPositionEvent[]; currentEquity: number }) {
  if (events.length === 0) {
    return (
      <p className="text-xs text-center py-8" style={{ color: "var(--text-muted)" }}>
        Equity curve appears once you have trade history.
      </p>
    );
  }

  // Reconstruct a rough cumulative-PnL curve from realized PnL events,
  // chronological order, ending at the current point. This is an
  // approximation: it doesn't account for collateral deposits/withdrawals
  // between trades, only realized PnL deltas — labeled as such below.
  const chronological = [...events].reverse();
  let running = 0;
  const points = chronological
    .filter((e) => e.realizedPnl !== null)
    .map((e) => {
      running += wadToNumber(BigInt(e.realizedPnl!));
      return running;
    });
  points.push(currentEquity);

  if (points.length < 2) {
    return (
      <p className="text-xs text-center py-8" style={{ color: "var(--text-muted)" }}>
        Not enough closed trades yet for an equity curve.
      </p>
    );
  }

  const min = Math.min(...points, 0);
  const max = Math.max(...points, 0);
  const range = max - min || 1;
  const w = 600;
  const h = 100;
  const stepX = w / (points.length - 1);

  const path = points
    .map((p, i) => {
      const x = i * stepX;
      const y = h - ((p - min) / range) * h;
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");

  const isUp = points[points.length - 1] >= points[0];

  return (
    <div>
      <svg viewBox={`0 0 ${w} ${h}`} className="w-full h-24" preserveAspectRatio="none">
        <path d={path} fill="none" stroke={isUp ? "var(--accent-long)" : "var(--accent-short)"} strokeWidth="2" />
      </svg>
      <p className="text-[10px] mt-1" style={{ color: "var(--text-muted)" }}>
        Approximate cumulative realized PnL over time — does not include collateral deposits/withdrawals between trades.
      </p>
    </div>
  );
}

export function PortfolioTab() {
  const { address } = useAccount();
  const [events, setEvents] = useState<SubgraphPositionEvent[]>([]);

  const positionCalls = MARKETS.flatMap((m: MarketInfo) => [
    { ...contracts.marginManager, functionName: "getPosition", args: [address ?? "0x0000000000000000000000000000000000000000", m.id, SIDE.LONG] },
    { ...contracts.marginManager, functionName: "getPosition", args: [address ?? "0x0000000000000000000000000000000000000000", m.id, SIDE.SHORT] },
  ]);
  const priceCalls = MARKETS.map((m: MarketInfo) => ({
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
      { ...contracts.vault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.vault, functionName: "lockedOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
    ] as unknown as readonly { result?: unknown }[],
    query: { enabled: !!address, refetchInterval: 12_000 },
  });

  useEffect(() => {
    if (!address) return;
    fetchAccountHistory(address)
      .then(({ events }) => setEvents(events))
      .catch(() => setEvents([]));
  }, [address]);

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
  const vaultFree = (data?.[tailStart + 5]?.result as bigint | undefined) ?? 0n;
  const vaultLocked = (data?.[tailStart + 6]?.result as bigint | undefined) ?? 0n;

  const rows: { market: MarketInfo; label: string; position: RawPosition; currentPrice: bigint; accent: string }[] = [];
  let totalUnrealizedPnl = 0;

  MARKETS.forEach((market, i) => {
    const longPos = data?.[i * 2]?.result as RawPosition | undefined;
    const shortPos = data?.[i * 2 + 1]?.result as RawPosition | undefined;
    const currentPrice = (data?.[positionCalls.length + i]?.result as bigint | undefined) ?? 0n;

    if (longPos && longPos.size > 0n) {
      const pnl = computePnl(longPos.size, longPos.entryPrice, currentPrice, true);
      totalUnrealizedPnl += pnl;
      rows.push({ market, label: "LONG", position: longPos, currentPrice, accent: "var(--accent-long)" });
    }
    if (shortPos && shortPos.size > 0n) {
      const pnl = computePnl(shortPos.size, shortPos.entryPrice, currentPrice, false);
      totalUnrealizedPnl += pnl;
      rows.push({ market, label: "SHORT", position: shortPos, currentPrice, accent: "var(--accent-short)" });
    }
  });

  const totalRealizedPnl = events
    .filter((e) => e.realizedPnl !== null)
    .reduce((sum, e) => sum + wadToNumber(BigInt(e.realizedPnl!)), 0);

  const totalLpShares = lpShares + stakedShares;
  const lpValueUsd = wadToNumber(totalLpShares) * wadToNumber(sharePrice);

  const netWorth = wadToNumber(walletBalance) + wadToNumber(vaultFree) + wadToNumber(vaultLocked) + lpValueUsd + totalUnrealizedPnl;
  const currentEquityForChart = wadToNumber(vaultFree) + wadToNumber(vaultLocked) + totalUnrealizedPnl;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Wallet (nUSD)" value={`$${formatAmount(walletBalance)}`} />
        <StatCard label="LP position value" value={`$${lpValueUsd.toFixed(2)}`} accent="var(--accent-info)" />
        <StatCard
          label="Unrealized PnL"
          value={formatPnl(totalUnrealizedPnl).text}
          accent={totalUnrealizedPnl >= 0 ? "var(--accent-long)" : "var(--accent-short)"}
        />
        <StatCard
          label="Realized PnL (all-time)"
          value={formatPnl(totalRealizedPnl).text}
          accent={totalRealizedPnl >= 0 ? "var(--accent-long)" : "var(--accent-short)"}
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <StatCard label="Free margin" value={`$${formatAmount(vaultFree)}`} accent="var(--accent-info)" sub="Available to open new positions" />
        <StatCard label="Used margin" value={`$${formatAmount(vaultLocked)}`} accent="var(--accent-warn)" sub="Locked in open positions/orders" />
      </div>

      <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
          Estimated net worth
        </div>
        <div className="font-mono text-2xl font-semibold tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${netWorth.toFixed(2)}
        </div>
        <p className="text-[11px] mt-1" style={{ color: "var(--text-muted)" }}>
          Wallet nUSD + Vault balance (free + locked) + LP position value + unrealized PnL.
          Doesn&apos;t include unclaimed staking rewards (different token) or gas costs.
        </p>
      </div>

      <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div className="text-xs mb-3" style={{ color: "var(--text-muted)" }}>
          Equity Curve
        </div>
        <EquitySparkline events={events} currentEquity={currentEquityForChart} />
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

      {earned > 0n && (
        <div className="border p-4 flex items-center justify-between" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <span className="text-xs" style={{ color: "var(--text-muted)" }}>Unclaimed staking rewards</span>
          <span className="font-mono text-sm tabular-nums" style={{ color: "var(--accent-long)" }}>
            {formatAmount(earned, 4)} nRWD
          </span>
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