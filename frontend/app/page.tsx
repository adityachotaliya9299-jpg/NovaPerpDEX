"use client";

import { useState } from "react";
import { Header } from "@/components/Header";
import { TabNav, type Tab } from "@/components/TabNav";
import { TradePanel } from "@/components/TradePanel";
import { PositionList } from "@/components/PositionList";
import { MarketStats } from "@/components/MarketStats";
import { OrdersTab } from "@/components/OrdersTab";
import { StopLossTab } from "@/components/StopLossTab";
import { EarnTab } from "@/components/EarnTab";
import { PortfolioTab } from "@/components/PortfolioTab";

export default function TradePage() {
  const [tab, setTab] = useState<Tab>("trade");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="min-h-screen flex flex-col" style={{ background: "var(--bg-base)" }}>
      <Header />
      <TabNav active={tab} onChange={setTab} />

      <main className="flex-1 max-w-screen-xl mx-auto w-full px-4 py-6">
        {tab === "trade" && (
          <div className="grid grid-cols-1 lg:grid-cols-[340px_1fr] gap-4 items-start">
            <TradePanel onTraded={() => setRefreshKey((k) => k + 1)} />
            <div className="space-y-4">
              <PositionList refreshKey={refreshKey} />
            </div>
          </div>
        )}

        {tab === "orders" && <OrdersTab />}
        {tab === "stops" && <StopLossTab />}
        {tab === "earn" && <EarnTab />}
        {tab === "portfolio" && <PortfolioTab />}
      </main>

      {tab === "trade" && (
        <div className="sticky bottom-0">
          <MarketStats />
        </div>
      )}
    </div>
  );
}