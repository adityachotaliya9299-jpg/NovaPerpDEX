"use client";

import { useAccount, useReadContracts } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import {
  formatAmount,
  formatPnl,
  computePnl,
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

function StatCard({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>
        {label}
      </div>
      <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: accent ?? "var(--text-primary)" }}>
        {value}
      </div>
    </div>
  );
}

export function PortfolioTab() {
  const { address } = useAccount();

  const { data } = useReadContracts({
    contracts: [
      { ...contracts.marginManager, functionName: "getPosition", args: [address ?? "0x0000000000000000000000000000000000000000", ETH_USD_MARKET, SIDE.LONG] },
      { ...contracts.marginManager, functionName: "getPosition", args: [address ?? "0x0000000000000000000000000000000000000000", ETH_USD_MARKET, SIDE.SHORT] },
      { ...contracts.priceFeed, functionName: "getPrice", args: [ETH_USD_MARKET] },
      { ...contracts.lpVault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.lpVault, functionName: "sharePrice" },
      { ...contracts.rewardDistributor, functionName: "stakedOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.rewardDistributor, functionName: "earned", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.collateralToken, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
    ],
    query: { enabled: !!address, refetchInterval: 12_000 },
  });

  if (!address) {
    return (
      <div className="border p-12 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm" style={{ color: "var(--text-muted)" }}>
          Connect your wallet to view your portfolio.
        </p>
      </div>
    );
  }

  const longPos = data?.[0]?.result as RawPosition | undefined;
  const shortPos = data?.[1]?.result as RawPosition | undefined;
  const currentPrice = (data?.[2]?.result as bigint | undefined) ?? 0n;
  const lpShares = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const sharePrice = (data?.[4]?.result as bigint | undefined) ?? 0n;
  const stakedShares = (data?.[5]?.result as bigint | undefined) ?? 0n;
  const earned = (data?.[6]?.result as bigint | undefined) ?? 0n;
  const walletBalance = (data?.[7]?.result as bigint | undefined) ?? 0n;

  const hasLong = longPos && longPos.size > 0n;
  const hasShort = shortPos && shortPos.size > 0n;

  const longPnl = hasLong ? computePnl(longPos!.size, longPos!.entryPrice, currentPrice, true) : 0;
  const shortPnl = hasShort ? computePnl(shortPos!.size, shortPos!.entryPrice, currentPrice, false) : 0;
  const totalTradingPnl = longPnl + shortPnl;

  // LP value: shares the user holds directly + shares currently staked,
  // both priced at the same sharePrice (staking doesn't change the
  // underlying share's redemption value, only who's holding it).
  const totalLpShares = lpShares + stakedShares;
  const lpValueUsd = wadToNumber(totalLpShares) * wadToNumber(sharePrice);

  const netWorth = wadToNumber(walletBalance) + lpValueUsd + totalTradingPnl;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Wallet (nUSD)" value={`$${formatAmount(walletBalance)}`} />
        <StatCard label="LP position value" value={`$${lpValueUsd.toFixed(2)}`} accent="var(--accent-info)" />
        <StatCard
          label="Trading PnL (unrealized)"
          value={formatPnl(totalTradingPnl).text}
          accent={totalTradingPnl >= 0 ? "var(--accent-long)" : "var(--accent-short)"}
        />
        <StatCard label="Unclaimed rewards" value={`${formatAmount(earned, 4)} nRWD`} accent="var(--accent-long)" />
      </div>

      <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
          Estimated net worth
        </div>
        <div className="font-mono text-2xl font-semibold tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${netWorth.toFixed(2)}
        </div>
        <p className="text-[11px] mt-1" style={{ color: "var(--text-muted)" }}>
          Wallet nUSD + LP position value + unrealized trading PnL. Doesn&apos;t
          include unclaimed staking rewards (different token) or gas costs.
        </p>
      </div>

      {(hasLong || hasShort) && (
        <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
            <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
              Open Positions
            </span>
          </div>
          {hasLong && (
            <PortfolioPositionRow label="LONG" position={longPos!} currentPrice={currentPrice} accentColor="var(--accent-long)" />
          )}
          {hasShort && (
            <PortfolioPositionRow label="SHORT" position={shortPos!} currentPrice={currentPrice} accentColor="var(--accent-short)" />
          )}
        </div>
      )}

      {totalLpShares > 0n && (
        <div className="border p-4 flex items-center justify-between" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div>
            <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
              LP shares ({formatAmount(lpShares, 4)} held + {formatAmount(stakedShares, 4)} staked)
            </div>
            <div className="font-mono text-sm tabular-nums" style={{ color: "var(--text-primary)" }}>
              {formatAmount(totalLpShares, 6)} shares total
            </div>
          </div>
          <div className="text-right">
            <div className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
              Share price
            </div>
            <div className="font-mono text-sm tabular-nums" style={{ color: "var(--accent-info)" }}>
              ${formatAmount(sharePrice, 4)}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function PortfolioPositionRow({
  label,
  position,
  currentPrice,
  accentColor,
}: {
  label: string;
  position: RawPosition;
  currentPrice: bigint;
  accentColor: string;
}) {
  const isLong = position.side === SIDE.LONG;
  const pnl = computePnl(position.size, position.entryPrice, currentPrice, isLong);
  const { text: pnlText, colorClass: pnlColor } = formatPnl(pnl);
  const equity = wadToNumber(position.collateral) + pnl;
  const health = computeHealth(equity, position.size, MAINTENANCE_BPS);

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span className="font-semibold px-1.5 py-0.5" style={{ background: `${accentColor}22`, color: accentColor }}>
          {label}
        </span>
        <span style={{ color: "var(--text-muted)" }}>ETH-USD</span>
        <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${formatAmount(position.size)}
        </span>
      </div>
      <div className="flex items-center gap-3">
        <span className={`font-mono text-xs tabular-nums font-semibold ${pnlColor}`}>{pnlText}</span>
        <span className="text-[10px] font-mono tabular-nums" style={{ color: health > 0.5 ? "var(--accent-long)" : health > 0.25 ? "var(--accent-warn)" : "var(--accent-short)" }}>
          {(health * 100).toFixed(0)}% health
        </span>
      </div>
    </div>
  );
}