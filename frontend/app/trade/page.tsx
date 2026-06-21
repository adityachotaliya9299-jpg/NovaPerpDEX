"use client";

import { useState } from "react";
import { Header } from "@/components/Header";
import { MarketsSidebar } from "@/components/MarketsSidebar";
import { PriceChart } from "@/components/PriceChart";
import { TradePanel } from "@/components/TradePanel";
import { PositionList } from "@/components/PositionList";
import { OrdersTab } from "@/components/OrdersTab";
import { StopLossTab } from "@/components/StopLossTab";
import { EarnTab } from "@/components/EarnTab";
import { PortfolioTab } from "@/components/PortfolioTab";
import { HistoryTab } from "@/components/HistoryTab";
import { FundingChart } from "@/components/FundingChart";
import { MarketStats } from "@/components/MarketStats";

type BottomTab = "positions" | "orders" | "stops" | "earn" | "portfolio" | "history" | "funding";

const BOTTOM_TABS: { id: BottomTab; label: string }[] = [
  { id: "positions", label: "Positions" },
  { id: "orders", label: "Orders" },
  { id: "stops", label: "Stop-Loss" },
  { id: "earn", label: "Earn" },
  { id: "portfolio", label: "Portfolio" },
  { id: "history", label: "History" },
  { id: "funding", label: "Funding" },
];

export default function TradePage() {
  const [bottomTab, setBottomTab] = useState<BottomTab>("positions");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="min-h-screen flex flex-col" style={{ background: "var(--bg-base)" }}>
      <Header />

      {/* Terminal grid: markets | chart | trade panel */}
      <div className="flex-1 grid grid-cols-1 lg:grid-cols-[200px_1fr_360px]">
        <div className="hidden lg:block border-r" style={{ borderColor: "var(--border)" }}>
          <MarketsSidebar />
        </div>

        <div className="flex flex-col min-w-0">
          <PriceChart />
        </div>

        <div className="border-t lg:border-t-0 lg:border-l" style={{ borderColor: "var(--border)" }}>
          <div className="p-4">
            <TradePanel onTraded={() => setRefreshKey((k) => k + 1)} />
          </div>
        </div>
      </div>

      {/* Bottom data panel: positions / orders / stop-loss / earn / portfolio */}
      <div className="border-t" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <nav className="flex gap-1 px-4">
          {BOTTOM_TABS.map((t) => (
            <button
              key={t.id}
              onClick={() => setBottomTab(t.id)}
              className="px-4 py-2.5 text-sm font-medium transition-colors"
              style={{
                color: bottomTab === t.id ? "var(--text-primary)" : "var(--text-muted)",
                borderBottom: bottomTab === t.id ? "2px solid var(--accent-info)" : "2px solid transparent",
              }}
            >
              {t.label}
            </button>
          ))}
        </nav>
        <div className="px-4 pb-4 max-h-[340px] overflow-y-auto">
          {bottomTab === "positions" && <PositionList refreshKey={refreshKey} />}
          {bottomTab === "orders" && <OrdersTab />}
          {bottomTab === "stops" && <StopLossTab />}
          {bottomTab === "earn" && <EarnTab />}
          {bottomTab === "portfolio" && <PortfolioTab />}
          {bottomTab === "history" && <HistoryTab />}
          {bottomTab === "funding" && <FundingChart />}
        </div>
      </div>

      <div className="sticky bottom-0">
        <MarketStats />
      </div>
    </div>
  );
}