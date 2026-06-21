"use client";

import { createContext, useContext, useState, type ReactNode } from "react";
import { MARKETS, DEFAULT_MARKET, type MarketInfo } from "@/lib/markets";

interface MarketContextValue {
  activeMarket: MarketInfo;
  setActiveMarket: (market: MarketInfo) => void;
  markets: MarketInfo[];
}

const MarketContext = createContext<MarketContextValue | null>(null);

export function MarketProvider({ children }: { children: ReactNode }) {
  const [activeMarket, setActiveMarket] = useState<MarketInfo>(DEFAULT_MARKET);
  return (
    <MarketContext.Provider value={{ activeMarket, setActiveMarket, markets: MARKETS }}>
      {children}
    </MarketContext.Provider>
  );
}

export function useMarket(): MarketContextValue {
  const ctx = useContext(MarketContext);
  if (!ctx) throw new Error("useMarket must be used inside <MarketProvider>");
  return ctx;
}