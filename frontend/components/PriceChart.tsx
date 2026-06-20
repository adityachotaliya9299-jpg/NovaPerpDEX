"use client";

import { useEffect, useRef, useState } from "react";
import { createChart, ColorType, CandlestickSeries, type IChartApi, type ISeriesApi } from "lightweight-charts";
import { useReadContract } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { formatPrice } from "@/lib/utils/format";

/**
 * Historical candles come from CoinGecko's free, keyless public API
 * (/coins/ethereum/ohlc) — real ETH/USD market history, not synthetic data.
 * This is separate from the on-chain oracle: CoinGecko is purely for the
 * visual chart, OracleAggregator (Chainlink) is what actually prices
 * positions. The two are expected to be very close but not byte-identical,
 * since they're independent data sources updating on different cadences.
 *
 * CoinGecko's keyless tier: 30 calls/min, no API key, no signup. We poll
 * once every 60s, comfortably under that limit even with multiple browser
 * tabs open.
 */

type Candle = { time: number; open: number; high: number; low: number; close: number };

async function fetchCandles(days: "1" | "7" | "30"): Promise<Candle[]> {
  const res = await fetch(
    `https://api.coingecko.com/api/v3/coins/ethereum/ohlc?vs_currency=usd&days=${days}`
  );
  if (!res.ok) throw new Error(`CoinGecko returned ${res.status}`);
  const raw: [number, number, number, number, number][] = await res.json();
  return raw.map(([t, o, h, l, c]) => ({
    time: Math.floor(t / 1000),
    open: o,
    high: h,
    low: l,
    close: c,
  }));
}

const RANGES: { id: "1" | "7" | "30"; label: string }[] = [
  { id: "1", label: "1D" },
  { id: "7", label: "7D" },
  { id: "30", label: "30D" },
];

export function PriceChart() {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<ISeriesApi<"Candlestick"> | null>(null);
  const [range, setRange] = useState<"1" | "7" | "30">("1");
  const [loadError, setLoadError] = useState<string | null>(null);

  const { data: livePrice } = useReadContract({
    ...contracts.priceFeed,
    functionName: "getPrice",
    args: [ETH_USD_MARKET],
    query: { refetchInterval: 10_000 },
  });

  // Set up the chart instance once on mount.
  useEffect(() => {
    if (!containerRef.current) return;

    const chart = createChart(containerRef.current, {
      layout: {
        background: { type: ColorType.Solid, color: "transparent" },
        textColor: "#8b95ab",
        fontFamily: "ui-monospace, monospace",
      },
      grid: {
        vertLines: { color: "#1c2333" },
        horzLines: { color: "#1c2333" },
      },
      timeScale: { borderColor: "#2a3346", timeVisible: true },
      rightPriceScale: { borderColor: "#2a3346" },
      crosshair: { mode: 0 },
      autoSize: true,
    });

    const series = chart.addSeries(CandlestickSeries, {
      upColor: "#3ddc97",
      downColor: "#ff6b6b",
      borderVisible: false,
      wickUpColor: "#3ddc97",
      wickDownColor: "#ff6b6b",
    });

    chartRef.current = chart;
    seriesRef.current = series;

    return () => {
      chart.remove();
      chartRef.current = null;
      seriesRef.current = null;
    };
  }, []);

  // Load historical candles whenever the selected range changes.
  useEffect(() => {
    let cancelled = false;
    setLoadError(null);

    fetchCandles(range)
      .then((candles) => {
        if (cancelled || !seriesRef.current) return;
        seriesRef.current.setData(candles);
        chartRef.current?.timeScale().fitContent();
      })
      .catch((err) => {
        if (!cancelled) setLoadError(err.message ?? "Failed to load chart data");
      });

    return () => {
      cancelled = true;
    };
  }, [range]);

  // Overlay the live on-chain price as the most recent tick, so the chart
  // visibly moves with the same price that's actually pricing positions —
  // without this, the chart would only update once a minute on its own
  // polling cadence and would feel disconnected from the rest of the UI.
  useEffect(() => {
    if (!livePrice || !seriesRef.current) return;
    const priceNum = Number(livePrice) / 1e18;
    const nowSec = Math.floor(Date.now() / 1000);
    try {
      seriesRef.current.update({
        time: nowSec as never,
        open: priceNum,
        high: priceNum,
        low: priceNum,
        close: priceNum,
      });
    } catch {
      // lightweight-charts throws if `time` goes backwards relative to the
      // last point — harmless to ignore, the next successful tick recovers.
    }
  }, [livePrice]);

  return (
    <div className="flex flex-col h-full min-h-[420px]">
      <div
        className="flex items-center justify-between px-4 py-2.5 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        <div className="flex items-center gap-3">
          <span className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
            ETH-USD
          </span>
          <span
            className="font-mono text-sm tabular-nums"
            style={{ color: livePrice ? "var(--accent-long)" : "var(--accent-warn)" }}
          >
            {livePrice ? formatPrice(livePrice) : "stale"}
          </span>
        </div>
        <div className="flex gap-1">
          {RANGES.map((r) => (
            <button
              key={r.id}
              onClick={() => setRange(r.id)}
              className="px-2.5 py-1 text-xs font-medium transition-colors"
              style={{
                color: range === r.id ? "var(--text-primary)" : "var(--text-muted)",
                background: range === r.id ? "var(--bg-elevated)" : "transparent",
              }}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      <div className="relative flex-1">
        {loadError && (
          <div
            className="absolute inset-0 flex items-center justify-center text-xs z-10"
            style={{ color: "var(--text-muted)", background: "var(--bg-base)" }}
          >
            Chart data unavailable ({loadError}). Live price still updates above.
          </div>
        )}
        <div ref={containerRef} className="w-full h-full" />
      </div>

      <div
        className="px-4 py-1.5 text-[10px] border-t"
        style={{ borderColor: "var(--border)", color: "var(--text-muted)" }}
      >
        Candles: CoinGecko market data · Live tick: Chainlink via OracleAggregator
      </div>
    </div>
  );
}