"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useReadContract } from "wagmi";
import { contracts } from "@/lib/contracts";
import { useMarket } from "@/lib/market-context";
import { formatPrice } from "@/lib/utils/format";
import { RefreshPrice } from "@/components/RefreshPrice";
import { Faucet } from "@/components/Faucet";

export function Header() {
  const { activeMarket } = useMarket();

  const { data: price } = useReadContract({
    ...contracts.priceFeed,
    functionName: "getPrice",
    args: [activeMarket.id],
    query: { refetchInterval: 10_000 },
  });

  return (
    <header
      className="border-b sticky top-0 z-50"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      <div className="max-w-screen-xl mx-auto px-4 h-14 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span
            className="text-sm font-semibold tracking-widest uppercase"
            style={{ color: "var(--accent-info)" }}
          >
            NovaPerpDEX
          </span>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1.5">
              <span className="text-xs font-medium" style={{ color: "var(--text-muted)" }}>
                {activeMarket.symbol}
              </span>
              <span
                className="text-xs px-1.5 py-0.5 text-[10px]"
                style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}
              >
                PERP
              </span>
            </div>
            <span
              className="font-mono text-base font-semibold tabular-nums"
              style={{ color: price ? "var(--text-primary)" : "var(--accent-warn)" }}
            >
              {price ? formatPrice(price) : "stale"}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-4">
          <a href="/vaults" className="text-xs font-medium hover:opacity-80" style={{ color: "var(--text-muted)" }}>
            Vaults
          </a>
          <a href="/risk" className="text-xs font-medium hover:opacity-80" style={{ color: "var(--text-muted)" }}>
            Risk
          </a>
          <a href="/rewards" className="text-xs font-medium hover:opacity-80" style={{ color: "var(--text-muted)" }}>
            Rewards
          </a>
          <Faucet />
          <RefreshPrice />
          <ConnectButton accountStatus="address" chainStatus="icon" showBalance={false} />
        </div>
      </div>
    </header>
  );
}