"use client";

import { useEffect, useState } from "react";
import { useMarket } from "@/lib/market-context";
import { fetchFundingHistory, type SubgraphFundingUpdate } from "@/lib/subgraph";
import { wadToNumber } from "@/lib/utils/format";

function ratePerYear(ratePerSecond: string): number {
  return wadToNumber(BigInt(ratePerSecond)) * 365 * 24 * 3600 * 100;
}

export function FundingChart() {
  const { activeMarket } = useMarket();
  const [updates, setUpdates] = useState<SubgraphFundingUpdate[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchFundingHistory(activeMarket.id)
      .then((data) => {
        if (!cancelled) setUpdates(data);
      })
      .catch(() => {
        if (!cancelled) setUpdates([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [activeMarket.id]);

  if (loading) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Loading funding history…</p>
      </div>
    );
  }

  if (updates.length === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>No funding updates yet</p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>
          Funding updates persist whenever updateFunding() is called on {activeMarket.symbol} — typically
          by the keeper bot or any trade interaction.
        </p>
      </div>
    );
  }

  const rates = updates.map((u) => ratePerYear(u.ratePerSecond));
  const maxAbs = Math.max(...rates.map(Math.abs), 0.01);
  const latest = updates[updates.length - 1];
  const latestRate = ratePerYear(latest.ratePerSecond);

  return (
    <div className="border" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="px-4 py-2.5 border-b flex items-center justify-between" style={{ borderColor: "var(--border)" }}>
        <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Funding Rate History — {activeMarket.symbol}
        </span>
        <span
          className="font-mono text-sm tabular-nums font-semibold"
          style={{ color: latestRate >= 0 ? "var(--accent-long)" : "var(--accent-short)" }}
        >
          {latestRate >= 0 ? "+" : ""}{latestRate.toFixed(4)}%/yr
        </span>
      </div>

      <div className="p-4">
        <div className="flex items-end gap-0.5 h-32">
          {rates.map((r, i) => {
            const heightPct = Math.max(4, (Math.abs(r) / maxAbs) * 100);
            const isPositive = r >= 0;
            return (
              <div
                key={updates[i].id}
                className="flex-1 flex flex-col justify-end h-full"
                title={`${r >= 0 ? "+" : ""}${r.toFixed(4)}%/yr`}
              >
                <div
                  className="w-full transition-all"
                  style={{
                    height: `${heightPct}%`,
                    background: isPositive ? "var(--accent-long)" : "var(--accent-short)",
                    opacity: 0.8,
                  }}
                />
              </div>
            );
          })}
        </div>
        <div className="flex justify-between text-[10px] mt-2" style={{ color: "var(--text-muted)" }}>
          <span>{new Date(Number(updates[0].timestamp) * 1000).toLocaleDateString()}</span>
          <span>{new Date(Number(updates[updates.length - 1].timestamp) * 1000).toLocaleDateString()}</span>
        </div>
      </div>

      <div className="px-4 py-2 border-t text-[11px]" style={{ borderColor: "var(--border)", color: "var(--text-muted)" }}>
        Positive bars: longs pay shorts (longs crowded). Negative bars: shorts pay longs.
        Updates persist whenever updateFunding() is called — not on a fixed schedule.
      </div>
    </div>
  );
}