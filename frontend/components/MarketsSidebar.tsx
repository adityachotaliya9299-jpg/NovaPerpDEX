"use client";

import { useReadContracts } from "wagmi";
import { contracts } from "@/lib/contracts";
import { useMarket } from "@/lib/market-context";
import { formatPrice } from "@/lib/utils/format";

export function MarketsSidebar() {
  const { activeMarket, setActiveMarket, markets } = useMarket();

  const { data } = useReadContracts({
    contracts: markets.map((m) => ({
      ...contracts.priceFeed,
      functionName: "getPrice",
      args: [m.id],
    })),
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
      {markets.map((m, i) => {
        const price = data?.[i]?.result as bigint | undefined;
        const isActive = m.id === activeMarket.id;
        return (
          <button
            key={m.id}
            onClick={() => setActiveMarket(m)}
            className="flex flex-col items-start gap-0.5 px-3 py-3 border-b text-left transition-colors"
            style={{
              borderColor: "var(--border)",
              background: isActive ? "var(--bg-elevated)" : "transparent",
            }}
          >
            <div className="flex items-center gap-2 w-full">
              <span
                className="text-sm font-semibold"
                style={{ color: isActive ? "var(--text-primary)" : "var(--text-muted)" }}
              >
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
        );
      })}
    </div>
  );
}