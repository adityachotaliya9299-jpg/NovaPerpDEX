"use client";

import { useEffect } from "react";
import { useAccount, useReadContracts } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import {
  formatPrice,
  formatAmount,
  formatPnl,
  computePnl,
  estimateLiqPrice,
  computeHealth,
  wadToNumber,
  SIDE,
} from "@/lib/utils/format";

const MAINTENANCE_BPS = 200;

interface RawPosition {
  size: bigint;
  collateral: bigint;
  entryPrice: bigint;
  side: number;
}

interface PositionRowProps {
  label: string;
  position: RawPosition;
  currentPrice: bigint;
  accentColor: string;
}

function PositionRow({ label, position, currentPrice, accentColor }: PositionRowProps) {
  const isLong = position.side === SIDE.LONG;
  const pnl = computePnl(position.size, position.entryPrice, currentPrice, isLong);
  const { text: pnlText, colorClass: pnlColor } = formatPnl(pnl);
  const equity = wadToNumber(position.collateral) + pnl;
  const health = computeHealth(equity, position.size, MAINTENANCE_BPS);
  const liqPrice = estimateLiqPrice(
    position.size,
    position.collateral,
    position.entryPrice,
    MAINTENANCE_BPS,
    isLong
  );

  const healthColor =
    health > 0.5
      ? "var(--accent-long)"
      : health > 0.25
      ? "var(--accent-warn)"
      : "var(--accent-short)";

  const healthBarBg =
    health > 0.5
      ? "linear-gradient(90deg, var(--accent-long), var(--accent-warn))"
      : health > 0.25
      ? "linear-gradient(90deg, var(--accent-warn), var(--accent-short))"
      : "var(--accent-short)";

  return (
    <div
      className="p-4 border-b last:border-b-0"
      style={{ borderColor: "var(--border)" }}
    >
      {/* Header row */}
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <span
            className="text-xs font-semibold px-1.5 py-0.5"
            style={{ background: `${accentColor}22`, color: accentColor }}
          >
            {label}
          </span>
          <span className="text-sm font-medium" style={{ color: "var(--text-primary)" }}>
            ETH-USD
          </span>
        </div>
        <span className={`font-mono text-sm tabular-nums font-semibold ${pnlColor}`}>
          {pnlText}
        </span>
      </div>

      {/* Metrics grid */}
      <div className="grid grid-cols-3 gap-3 mb-3 text-xs">
        <div>
          <div style={{ color: "var(--text-muted)" }} className="mb-0.5">
            Size
          </div>
          <div className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
            ${formatAmount(position.size)}
          </div>
        </div>
        <div>
          <div style={{ color: "var(--text-muted)" }} className="mb-0.5">
            Entry
          </div>
          <div className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
            {formatPrice(position.entryPrice)}
          </div>
        </div>
        <div>
          <div style={{ color: "var(--text-muted)" }} className="mb-0.5">
            Liq. Price
          </div>
          <div className="font-mono tabular-nums" style={{ color: "var(--accent-warn)" }}>
            {liqPrice > 0 ? `$${liqPrice.toFixed(2)}` : "—"}
          </div>
        </div>
      </div>

      {/* Health bar — the signature gradient element */}
      <div>
        <div className="flex items-center justify-between mb-1">
          <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
            Health
          </span>
          <span
            className="text-[10px] font-mono tabular-nums"
            style={{ color: healthColor }}
          >
            {(health * 100).toFixed(0)}%
          </span>
        </div>
        <div
          className="h-1.5 rounded-full overflow-hidden"
          style={{ background: "var(--bg-elevated)" }}
        >
          <div
            className="h-full rounded-full transition-all duration-700"
            style={{
              width: `${Math.max(2, health * 100)}%`,
              background: healthBarBg,
            }}
          />
        </div>
      </div>
    </div>
  );
}

export function PositionList({ refreshKey }: { refreshKey?: number }) {
  const { address } = useAccount();

  const { data, refetch } = useReadContracts({
    contracts: [
      {
        ...contracts.marginManager,
        functionName: "getPosition",
        args: [
          address ?? "0x0000000000000000000000000000000000000000",
          ETH_USD_MARKET,
          SIDE.LONG,
        ],
      },
      {
        ...contracts.marginManager,
        functionName: "getPosition",
        args: [
          address ?? "0x0000000000000000000000000000000000000000",
          ETH_USD_MARKET,
          SIDE.SHORT,
        ],
      },
      {
        ...contracts.priceFeed,
        functionName: "getPrice",
        args: [ETH_USD_MARKET],
      },
    ],
    query: {
      enabled: !!address,
      refetchInterval: 10_000,
    },
  });

  // Force a fresh read whenever the parent signals a trade completed
  useEffect(() => {
    if (refreshKey) refetch();
  }, [refreshKey, refetch]);

  const longPos = data?.[0]?.result as RawPosition | undefined;
  const shortPos = data?.[1]?.result as RawPosition | undefined;
  const currentPrice = (data?.[2]?.result as bigint | undefined) ?? 0n;

  const hasLong = longPos && longPos.size > 0n;
  const hasShort = shortPos && shortPos.size > 0n;

  if (!address) {
    return (
      <div
        className="border p-8 text-center"
        style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
      >
        <p className="text-sm" style={{ color: "var(--text-muted)" }}>
          Connect your wallet to view positions
        </p>
      </div>
    );
  }

  if (!hasLong && !hasShort) {
    return (
      <div
        className="border p-8 text-center"
        style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
      >
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>
          No open positions
        </p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>
          Open a long or short using the panel on the left.
        </p>
      </div>
    );
  }

  return (
    <div
      className="border overflow-hidden"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      <div
        className="px-4 py-2.5 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        <span
          className="text-xs font-medium uppercase tracking-wider"
          style={{ color: "var(--text-muted)" }}
        >
          Your Positions
        </span>
      </div>
      {hasLong && (
        <PositionRow
          label="LONG"
          position={longPos!}
          currentPrice={currentPrice}
          accentColor="var(--accent-long)"
        />
      )}
      {hasShort && (
        <PositionRow
          label="SHORT"
          position={shortPos!}
          currentPrice={currentPrice}
          accentColor="var(--accent-short)"
        />
      )}
    </div>
  );
}