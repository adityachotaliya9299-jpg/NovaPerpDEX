"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useReadContract } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { formatPrice } from "@/lib/utils/format";
import { RefreshPrice } from "@/components/RefreshPrice";
import { Faucet } from "@/components/Faucet";

export function Header() {
  const { data: price } = useReadContract({
    ...contracts.priceFeed,
    functionName: "getPrice",
    args: [ETH_USD_MARKET],
    query: { refetchInterval: 10_000 },
  });

  return (
    <header
      className="border-b sticky top-0 z-50"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      <div className="max-w-screen-xl mx-auto px-4 h-14 flex items-center justify-between">
        {/* Left: logo + market */}
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
                ETH-USD
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

        {/* Right: faucet + keeper control + connect */}
        <div className="flex items-center gap-3">
          <Faucet />
          <RefreshPrice />
          <ConnectButton accountStatus="address" chainStatus="icon" showBalance={false} />
        </div>
      </div>
    </header>
  );
}