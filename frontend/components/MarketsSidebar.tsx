"use client";

import { useReadContract } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { formatPrice } from "@/lib/utils/format";

const MARKETS = [
  { id: "ETH-USD", market: ETH_USD_MARKET, label: "ETH", sub: "Ethereum" },
];

export function MarketsSidebar() {
  const { data: price } = useReadContract({
    ...contracts.priceFeed,
    functionName: "getPrice",
    args: [ETH_USD_MARKET],
    query: { refetchInterval: 10_000 },
  });

  return (
    <div className="h-full flex flex-col">
      <div className="px-3 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
        <span
          className="text-[10px] font-semibold uppercase tracking-wide"
          style={{ color: "var(--text-muted)" }}
        >
          Markets
        </span>
      </div>
      {MARKETS.map((m) => (
        <button
          key={m.id}
          className="flex flex-col items-start gap-0.5 px-3 py-3 border-b text-left transition-colors"
          style={{
            borderColor: "var(--border)",
            background: "var(--bg-elevated)",
          }}
        >
          <div className="flex items-center gap-2 w-full">
            <span className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
              {m.label}
            </span>
            <span
              className="text-[9px] px-1 py-0.5"
              style={{ background: "var(--bg-surface)", color: "var(--text-muted)" }}
            >
              PERP
            </span>
          </div>
          <span
            className="font-mono text-xs tabular-nums"
            style={{ color: price ? "var(--accent-long)" : "var(--accent-warn)" }}
          >
            {price ? formatPrice(price) : "stale"}
          </span>
        </button>
      ))}
      <div
        className="px-3 py-3 text-[11px]"
        style={{ color: "var(--text-muted)" }}
      >
        More markets coming soon.
      </div>
    </div>
  );
}