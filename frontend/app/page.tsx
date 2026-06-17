"use client";

import { useState } from "react";
import { Header } from "@/components/Header";
import { TradePanel } from "@/components/TradePanel";
import { PositionList } from "@/components/PositionList";
import { MarketStats } from "@/components/MarketStats";

export default function TradePage() {
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div
      className="min-h-screen flex flex-col"
      style={{ background: "var(--bg-base)" }}
    >
      <Header />

      <main className="flex-1 max-w-screen-xl mx-auto w-full px-4 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-[340px_1fr] gap-4 items-start">
          {/* Left: trade panel */}
          <TradePanel onTraded={() => setRefreshKey((k) => k + 1)} />

          {/* Right: positions */}
          <div className="space-y-4">
            <PositionList refreshKey={refreshKey} />
          </div>
        </div>
      </main>

      {/* Bottom: market stats bar */}
      <div className="sticky bottom-0">
        <MarketStats />
      </div>
    </div>
  );
}