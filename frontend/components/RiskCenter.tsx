"use client";

import { useEffect, useState } from "react";
import { useReadContracts } from "wagmi";
import { contracts } from "@/lib/contracts";
import { MARKETS } from "@/lib/markets";
import { getMarketById } from "@/lib/markets";
import { formatAmount, formatPrice, wadToNumber } from "@/lib/utils/format";
import { fetchLargestPositions, fetchRecentLiquidations, type SubgraphPosition, type SubgraphLiquidation } from "@/lib/subgraph";

/**
 * Protocol Health Score
 *
 * This is NOT an on-chain value; there is no contract function that returns
 * "protocol health." It's a transparent, documented composite of three
 * factors the protocol actually tracks, weighted and shown individually so
 * nothing is a black box:
 *
 *   1. Insurance coverage ratio (40% weight) — insurance fund balance as a
 *      percentage of total open interest. Higher is safer (more reserve to
 *      absorb liquidation shortfalls before bad debt is socialized).
 *   2. OI balance (30% weight) — how close long/short OI is to 50/50. A
 *      heavily skewed book means more correlated risk on one side.
 *   3. Vault utilization (30% weight) — LP vault TVL relative to total open
 *      interest. Lower utilization means more buffer for trader profits to
 *      be paid out without strain.
 *
 * Each factor is normalized to 0-100 and combined by weight. This formula
 * is a judgment call, not a protocol-defined metric — it's shown with its
 * components so anyone can see exactly what feeds the number rather than
 * trusting a single opaque score.
 */

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

export function RiskCenter() {
  const [largestPositions, setLargestPositions] = useState<SubgraphPosition[]>([]);
  const [recentLiquidations, setRecentLiquidations] = useState<SubgraphLiquidation[]>([]);
  const [loadingSubgraph, setLoadingSubgraph] = useState(true);

  const { data } = useReadContracts({
    contracts: [
      { ...contracts.lpVault, functionName: "totalAssets" },
      { ...contracts.insuranceFund, functionName: "balance" },
      ...MARKETS.flatMap((m) => [
        { ...contracts.marginManager, functionName: "longOpenInterest", args: [m.id] },
        { ...contracts.marginManager, functionName: "shortOpenInterest", args: [m.id] },
      ]),
    ],
    query: { refetchInterval: 15_000 },
  });

  useEffect(() => {
    let cancelled = false;
    Promise.all([fetchLargestPositions(), fetchRecentLiquidations()])
      .then(([positions, liqs]) => {
        if (!cancelled) {
          setLargestPositions(positions);
          setRecentLiquidations(liqs);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setLargestPositions([]);
          setRecentLiquidations([]);
        }
      })
      .finally(() => {
        if (!cancelled) setLoadingSubgraph(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const tvl = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const insuranceBalance = (data?.[1]?.result as bigint | undefined) ?? 0n;

  let totalLongOi = 0n;
  let totalShortOi = 0n;
  MARKETS.forEach((_, i) => {
    const long = (data?.[2 + i * 2]?.result as bigint | undefined) ?? 0n;
    const short = (data?.[2 + i * 2 + 1]?.result as bigint | undefined) ?? 0n;
    totalLongOi += long;
    totalShortOi += short;
  });
  const totalOi = totalLongOi + totalShortOi;

  // --- Component scores ---
  const insuranceCoverageRatio = totalOi > 0n ? wadToNumber(insuranceBalance) / wadToNumber(totalOi) : 1;
  const insuranceScore = clamp(insuranceCoverageRatio * 1000, 0, 100); // 10% coverage -> 100 score

  const skewRatio = totalOi > 0n ? Math.abs(wadToNumber(totalLongOi) - wadToNumber(totalShortOi)) / wadToNumber(totalOi) : 0;
  const balanceScore = clamp(100 - skewRatio * 100, 0, 100);

  const utilization = wadToNumber(tvl) > 0 ? wadToNumber(totalOi) / wadToNumber(tvl) : 0;
  const utilizationScore = clamp(100 - utilization * 100, 0, 100);

  const healthScore = Math.round(insuranceScore * 0.4 + balanceScore * 0.3 + utilizationScore * 0.3);

  const healthColor =
    healthScore >= 70 ? "var(--accent-long)" : healthScore >= 40 ? "var(--accent-warn)" : "var(--accent-short)";

  return (
    <div className="space-y-6">
      {/* Health score hero */}
      <div className="border p-6 flex items-center gap-6" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div>
          <div className="font-mono text-5xl font-bold tabular-nums" style={{ color: healthColor }}>
            {healthScore}
          </div>
          <div className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>
            Protocol Health Score
          </div>
        </div>
        <div className="flex-1 grid grid-cols-3 gap-4 text-xs">
          <ScoreBar label="Insurance Coverage" score={insuranceScore} weight="40%" />
          <ScoreBar label="OI Balance" score={balanceScore} weight="30%" />
          <ScoreBar label="Vault Utilization" score={utilizationScore} weight="30%" />
        </div>
      </div>

      <p className="text-[11px] px-1" style={{ color: "var(--text-muted)" }}>
        This score is a transparent composite, not an on-chain value — see the three weighted
        components above. It is a judgment-call formula, shown with its inputs rather than as a
        black box.
      </p>

      {/* Live stats grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Total Open Interest" value={`$${formatAmount(totalOi)}`} />
        <StatCard label="LP Vault TVL" value={`$${formatAmount(tvl)}`} accent="var(--accent-info)" />
        <StatCard label="Insurance Fund" value={`$${formatAmount(insuranceBalance)}`} accent="var(--accent-long)" />
        <StatCard
          label="Long / Short Ratio"
          value={totalOi > 0n ? `${((wadToNumber(totalLongOi) / wadToNumber(totalOi)) * 100).toFixed(0)}% / ${((wadToNumber(totalShortOi) / wadToNumber(totalOi)) * 100).toFixed(0)}%` : "—"}
        />
      </div>

      {/* Largest open positions */}
      <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
          <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
            Largest Open Positions — All Accounts
          </span>
        </div>
        {loadingSubgraph ? (
          <p className="text-xs text-center py-6" style={{ color: "var(--text-muted)" }}>Loading…</p>
        ) : largestPositions.length === 0 ? (
          <p className="text-xs text-center py-6" style={{ color: "var(--text-muted)" }}>No open positions yet.</p>
        ) : (
          largestPositions.map((p) => {
            const market = getMarketById(p.market);
            const isLong = p.side === 0;
            return (
              <div key={p.id} className="p-3 border-b last:border-b-0 flex items-center justify-between text-xs" style={{ borderColor: "var(--border)" }}>
                <div className="flex items-center gap-3">
                  <span style={{ color: isLong ? "var(--accent-long)" : "var(--accent-short)" }}>{isLong ? "LONG" : "SHORT"}</span>
                  <span className="text-[10px] px-1 py-0.5" style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}>
                    {market.symbol}
                  </span>
                  <span style={{ color: "var(--text-muted)" }}>
                    {p.account.slice(0, 6)}…{p.account.slice(-4)}
                  </span>
                </div>
                <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
                  ${formatAmount(BigInt(p.size))}
                </span>
              </div>
            );
          })
        )}
      </div>

      {/* Recent liquidations */}
      <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
          <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
            Recent Liquidations
          </span>
        </div>
        {loadingSubgraph ? (
          <p className="text-xs text-center py-6" style={{ color: "var(--text-muted)" }}>Loading…</p>
        ) : recentLiquidations.length === 0 ? (
          <p className="text-xs text-center py-6" style={{ color: "var(--text-muted)" }}>No liquidations yet — good sign.</p>
        ) : (
          recentLiquidations.map((l) => {
            const market = getMarketById(l.market);
            const isLong = l.side === 0;
            return (
              <div key={l.id} className="p-3 border-b last:border-b-0 flex items-center justify-between text-xs" style={{ borderColor: "var(--border)" }}>
                <div className="flex items-center gap-3">
                  <span style={{ color: "var(--accent-short)" }}>LIQUIDATED</span>
                  <span className="text-[10px] px-1 py-0.5" style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}>
                    {market.symbol}
                  </span>
                  <span style={{ color: isLong ? "var(--accent-long)" : "var(--accent-short)" }}>{isLong ? "LONG" : "SHORT"}</span>
                </div>
                <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
                  ${formatAmount(BigInt(l.size))} @ {formatPrice(BigInt(l.price))}
                </span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}

function ScoreBar({ label, score, weight }: { label: string; score: number; weight: string }) {
  const color = score >= 70 ? "var(--accent-long)" : score >= 40 ? "var(--accent-warn)" : "var(--accent-short)";
  return (
    <div>
      <div className="flex justify-between mb-1">
        <span style={{ color: "var(--text-muted)" }}>{label} ({weight})</span>
        <span className="font-mono tabular-nums" style={{ color }}>{score.toFixed(0)}</span>
      </div>
      <div className="h-1.5 rounded-full overflow-hidden" style={{ background: "var(--bg-elevated)" }}>
        <div className="h-full rounded-full" style={{ width: `${score}%`, background: color }} />
      </div>
    </div>
  );
}

function StatCard({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>{label}</div>
      <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: accent ?? "var(--text-primary)" }}>
        {value}
      </div>
    </div>
  );
}