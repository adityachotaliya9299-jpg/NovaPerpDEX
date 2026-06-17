"use client";

import { useReadContracts } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { formatAmount, formatFundingRate } from "@/lib/utils/format";

export function MarketStats() {
  const { data } = useReadContracts({
    contracts: [
      {
        ...contracts.marginManager,
        functionName: "longOpenInterest",
        args: [ETH_USD_MARKET],
      },
      {
        ...contracts.marginManager,
        functionName: "shortOpenInterest",
        args: [ETH_USD_MARKET],
      },
      {
        ...contracts.fundingRateEngine,
        functionName: "currentFundingRate",
        args: [ETH_USD_MARKET],
      },
    ],
    query: { refetchInterval: 15_000 },
  });

  const longOI = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const shortOI = (data?.[1]?.result as bigint | undefined) ?? 0n;
  const fundingRate = (data?.[2]?.result as bigint | undefined) ?? 0n;

  const totalOI = longOI + shortOI;
  const longPct = totalOI > 0n ? Number((longOI * 10000n) / totalOI) / 100 : 50;
  const shortPct = 100 - longPct;
  const isLongHeavy = longOI >= shortOI;

  return (
    <div
      className="border-t px-4 py-3"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      <div className="max-w-screen-xl mx-auto flex flex-wrap items-center gap-6 text-xs">
        {/* OI skew bar */}
        <div className="flex items-center gap-3 flex-1 min-w-[260px] max-w-sm">
          <span style={{ color: "var(--text-muted)" }} className="shrink-0">
            Open Interest
          </span>
          <div className="flex items-center gap-1.5 flex-1">
            <span className="font-mono tabular-nums" style={{ color: "var(--accent-long)" }}>
              L {longPct.toFixed(1)}%
            </span>
            {/* Signature health-bar motif */}
            <div
              className="flex-1 h-1.5 rounded-full overflow-hidden"
              style={{ background: "var(--bg-elevated)" }}
            >
              <div
                className="h-full rounded-full transition-all duration-500"
                style={{
                  width: `${longPct}%`,
                  background: isLongHeavy
                    ? "linear-gradient(90deg, var(--accent-long), var(--accent-warn))"
                    : "linear-gradient(90deg, var(--accent-warn), var(--accent-short))",
                }}
              />
            </div>
            <span className="font-mono tabular-nums" style={{ color: "var(--accent-short)" }}>
              S {shortPct.toFixed(1)}%
            </span>
          </div>
        </div>

        {/* OI notional values */}
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5">
            <span style={{ color: "var(--text-muted)" }}>Long OI</span>
            <span className="font-mono tabular-nums" style={{ color: "var(--accent-long)" }}>
              ${formatAmount(longOI)}
            </span>
          </div>
          <div className="flex items-center gap-1.5">
            <span style={{ color: "var(--text-muted)" }}>Short OI</span>
            <span className="font-mono tabular-nums" style={{ color: "var(--accent-short)" }}>
              ${formatAmount(shortOI)}
            </span>
          </div>
        </div>

        {/* Funding rate */}
        <div className="flex items-center gap-1.5">
          <span style={{ color: "var(--text-muted)" }}>Funding</span>
          <span
            className="font-mono tabular-nums"
            style={{
              color: fundingRate >= 0n ? "var(--accent-long)" : "var(--accent-short)",
            }}
          >
            {formatFundingRate(fundingRate)}
          </span>
          <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
            {fundingRate >= 0n ? "(longs pay shorts)" : "(shorts pay longs)"}
          </span>
        </div>
      </div>
    </div>
  );
}