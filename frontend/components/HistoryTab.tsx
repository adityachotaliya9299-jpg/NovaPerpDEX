"use client";

import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { getMarketById } from "@/lib/markets";
import { formatAmount, formatPrice, formatPnl, wadToNumber, SIDE } from "@/lib/utils/format";
import { fetchAccountHistory, type SubgraphPositionEvent, type SubgraphLiquidation } from "@/lib/subgraph";

type HistoryRow =
  | { type: "event"; data: SubgraphPositionEvent; timestamp: number }
  | { type: "liquidation"; data: SubgraphLiquidation; timestamp: number };

function timeAgo(unixSeconds: number): string {
  const diffSec = Math.floor(Date.now() / 1000) - unixSeconds;
  if (diffSec < 60) return `${diffSec}s ago`;
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
  return `${Math.floor(diffSec / 86400)}d ago`;
}

function EventRow({ event }: { event: SubgraphPositionEvent }) {
  const market = getMarketById(event.market);
  const isIncrease = event.kind === "INCREASE";
  const isLong = event.side === SIDE.LONG;
  const ts = Number(event.timestamp);

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between gap-3" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span
          className="font-semibold px-1.5 py-0.5"
          style={{
            background: isIncrease ? "var(--accent-info)22" : "var(--bg-elevated)",
            color: isIncrease ? "var(--accent-info)" : "var(--text-muted)",
          }}
        >
          {isIncrease ? "OPEN/INCREASE" : "DECREASE/CLOSE"}
        </span>
        <span className="text-[10px] px-1 py-0.5" style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}>
          {market.symbol}
        </span>
        {event.side !== null && (
          <span style={{ color: isLong ? "var(--accent-long)" : "var(--accent-short)" }}>
            {isLong ? "LONG" : "SHORT"}
          </span>
        )}
        <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${formatAmount(BigInt(event.sizeDelta))}
        </span>
        <span style={{ color: "var(--text-muted)" }}>@ {formatPrice(BigInt(event.price))}</span>
        {event.realizedPnl !== null && (
          <span className={`font-mono ${wadToNumber(BigInt(event.realizedPnl)) >= 0 ? "text-accent-long" : "text-accent-short"}`}>
            {formatPnl(wadToNumber(BigInt(event.realizedPnl))).text}
          </span>
        )}
      </div>
      <div className="flex items-center gap-2 text-[10px]" style={{ color: "var(--text-muted)" }}>
        <span>{timeAgo(ts)}</span>
        <a
          href={`https://sepolia.etherscan.io/tx/${event.txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: "var(--accent-info)" }}
        >
          ↗
        </a>
      </div>
    </div>
  );
}

function LiquidationRow({ liq }: { liq: SubgraphLiquidation }) {
  const market = getMarketById(liq.market);
  const isLong = liq.side === SIDE.LONG;
  const ts = Number(liq.timestamp);

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between gap-3" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span className="font-semibold px-1.5 py-0.5" style={{ background: "var(--accent-short)22", color: "var(--accent-short)" }}>
          LIQUIDATED
        </span>
        <span className="text-[10px] px-1 py-0.5" style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}>
          {market.symbol}
        </span>
        <span style={{ color: isLong ? "var(--accent-long)" : "var(--accent-short)" }}>
          {isLong ? "LONG" : "SHORT"}
        </span>
        <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${formatAmount(BigInt(liq.size))}
        </span>
        <span style={{ color: "var(--text-muted)" }}>@ {formatPrice(BigInt(liq.price))}</span>
        <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
          keeper {liq.keeper.slice(0, 6)}…{liq.keeper.slice(-4)}
        </span>
      </div>
      <div className="flex items-center gap-2 text-[10px]" style={{ color: "var(--text-muted)" }}>
        <span>{timeAgo(ts)}</span>
        <a
          href={`https://sepolia.etherscan.io/tx/${liq.txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: "var(--accent-info)" }}
        >
          ↗
        </a>
      </div>
    </div>
  );
}

export function HistoryTab() {
  const { address } = useAccount();
  const [rows, setRows] = useState<HistoryRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!address) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);

    fetchAccountHistory(address)
      .then(({ events, liquidations }) => {
        if (cancelled) return;
        const merged: HistoryRow[] = [
          ...events.map((e) => ({ type: "event" as const, data: e, timestamp: Number(e.timestamp) })),
          ...liquidations.map((l) => ({ type: "liquidation" as const, data: l, timestamp: Number(l.timestamp) })),
        ];
        merged.sort((a, b) => b.timestamp - a.timestamp);
        setRows(merged);
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [address]);

  if (!address) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm" style={{ color: "var(--text-muted)" }}>Connect your wallet to view trade history.</p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Loading history…</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--accent-short)" }}>Failed to load history: {error}</p>
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>No history yet</p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Trades, closes, and liquidations will appear here.</p>
      </div>
    );
  }

  return (
    <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
        <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Trade History — All Markets
        </span>
      </div>
      {rows.map((row) =>
        row.type === "event" ? (
          <EventRow key={row.data.id} event={row.data} />
        ) : (
          <LiquidationRow key={row.data.id} liq={row.data} />
        )
      )}
    </div>
  );
}