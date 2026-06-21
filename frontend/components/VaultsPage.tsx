"use client";

import { useAccount, useReadContracts } from "wagmi";
import { contracts } from "@/lib/contracts";
import { MARKETS, type MarketInfo } from "@/lib/markets";
import { formatAmount, wadToNumber } from "@/lib/utils/format";
import { LPVaultPanel } from "@/components/LPVaultPanel";
import { StakingPanel } from "@/components/StakingPanel";

/**
 *   dedicated Vaults page. Surfaces three distinct pools that
 * are easy to conflate but are functionally separate contracts:
 *   - LPVault: the counterparty pool backing trader PnL (deposit/withdraw here)
 *   - InsuranceFund: a separate reserve covering liquidation shortfalls
 *     before any loss is socialized to LPs — LPs never deposit here directly
 *   - Vault: the low-level ledger holding every account's free/locked
 *     collateral, including the connected wallet's own trading balance
 */

function StatCard({ label, value, accent, sub }: { label: string; value: string; accent?: string; sub?: string }) {
  return (
    <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>{label}</div>
      <div className="font-mono text-xl tabular-nums font-semibold" style={{ color: accent ?? "var(--text-primary)" }}>
        {value}
      </div>
      {sub && <div className="text-[11px] mt-1" style={{ color: "var(--text-muted)" }}>{sub}</div>}
    </div>
  );
}

export function VaultsPage() {
  const { address } = useAccount();

  const positionCalls = MARKETS.flatMap((m: MarketInfo) => [
    { ...contracts.marginManager, functionName: "longOpenInterest", args: [m.id] },
    { ...contracts.marginManager, functionName: "shortOpenInterest", args: [m.id] },
  ]);

  const { data } = useReadContracts({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    contracts: [
      { ...contracts.lpVault, functionName: "totalAssets" },
      { ...contracts.lpVault, functionName: "totalSupply" },
      { ...contracts.lpVault, functionName: "sharePrice" },
      { ...contracts.insuranceFund, functionName: "balance" },
      { ...contracts.rewardDistributor, functionName: "rewardRate" },
      { ...contracts.rewardDistributor, functionName: "totalStaked" },
      { ...contracts.vault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.vault, functionName: "lockedOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      ...positionCalls,
    ] as any[],
    query: { refetchInterval: 15_000 },
  }) as { data: { result?: unknown }[] | undefined };

  const lpTvl = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const lpTotalSupply = (data?.[1]?.result as bigint | undefined) ?? 0n;
  const sharePrice = (data?.[2]?.result as bigint | undefined) ?? 0n;
  const insuranceBalance = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const rewardRate = (data?.[4]?.result as bigint | undefined) ?? 0n;
  const totalStaked = (data?.[5]?.result as bigint | undefined) ?? 0n;
  const myFree = (data?.[6]?.result as bigint | undefined) ?? 0n;
  const myLocked = (data?.[7]?.result as bigint | undefined) ?? 0n;

  let totalOi = 0n;
  MARKETS.forEach((_, i) => {
    const long = (data?.[8 + i * 2]?.result as bigint | undefined) ?? 0n;
    const short = (data?.[8 + i * 2 + 1]?.result as bigint | undefined) ?? 0n;
    totalOi += long + short;
  });

  // Utilization: how much of the LP pool's capital is "at risk" backing
  // open trader positions right now, vs sitting idle as free buffer.
  const utilization = wadToNumber(lpTvl) > 0 ? (wadToNumber(totalOi) / wadToNumber(lpTvl)) * 100 : 0;

  // Insurance coverage: insurance reserve as a percentage of total OI —
  // how much of a worst-case simultaneous shortfall the fund could absorb.
  const insuranceCoverage = wadToNumber(totalOi) > 0 ? (wadToNumber(insuranceBalance) / wadToNumber(totalOi)) * 100 : 0;

  return (
    <div className="space-y-6">
      {/* LP Vault */}
      <section>
        <h2 className="text-sm font-semibold mb-3" style={{ color: "var(--text-primary)" }}>
          LP Vault — Counterparty Pool
        </h2>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <StatCard label="TVL" value={`$${formatAmount(lpTvl)}`} accent="var(--accent-info)" />
          <StatCard label="Share Price" value={`$${formatAmount(sharePrice, 4)}`} />
          <StatCard
            label="Utilization"
            value={`${utilization.toFixed(1)}%`}
            accent={utilization < 50 ? "var(--accent-long)" : utilization < 80 ? "var(--accent-warn)" : "var(--accent-short)"}
            sub="Open interest vs TVL"
          />
          <StatCard label="Total Shares" value={formatAmount(lpTotalSupply, 4)} />
        </div>
        <LPVaultPanel />
      </section>

      {/* Staking */}
      <section>
        <h2 className="text-sm font-semibold mb-3" style={{ color: "var(--text-primary)" }}>
          Staking — Earn nRWD
        </h2>
        <div className="grid grid-cols-2 gap-4 mb-4">
          <StatCard
            label="Emission Status"
            value={rewardRate > 0n ? "Active" : "No active emission"}
            accent={rewardRate > 0n ? "var(--accent-long)" : "var(--text-muted)"}
          />
          <StatCard label="Total Staked" value={`${formatAmount(totalStaked, 4)} shares`} />
        </div>
        <StakingPanel />
      </section>

      {/* Insurance Fund */}
      <section>
        <h2 className="text-sm font-semibold mb-3" style={{ color: "var(--text-primary)" }}>
          Insurance Fund
        </h2>
        <div className="grid grid-cols-2 gap-4">
          <StatCard label="Fund Size" value={`$${formatAmount(insuranceBalance)}`} accent="var(--accent-long)" />
          <StatCard
            label="Coverage Ratio"
            value={`${insuranceCoverage.toFixed(2)}%`}
            sub="Of total open interest"
            accent={insuranceCoverage > 5 ? "var(--accent-long)" : insuranceCoverage > 1 ? "var(--accent-warn)" : "var(--accent-short)"}
          />
        </div>
        <p className="text-[11px] mt-3 px-1" style={{ color: "var(--text-muted)" }}>
          Seeded and managed by governance — there is no public deposit function for the
          Insurance Fund. It absorbs liquidation shortfalls before any loss is socialized
          to LPs.
        </p>
      </section>

      {/* Your Vault Balance */}
      {address && (
        <section>
          <h2 className="text-sm font-semibold mb-3" style={{ color: "var(--text-primary)" }}>
            Your Trading Balance
          </h2>
          <div className="grid grid-cols-2 gap-4">
            <StatCard label="Free (available)" value={`$${formatAmount(myFree)}`} accent="var(--accent-info)" />
            <StatCard label="Locked (in positions/orders)" value={`$${formatAmount(myLocked)}`} accent="var(--accent-warn)" />
          </div>
          <p className="text-[11px] mt-3 px-1" style={{ color: "var(--text-muted)" }}>
            This is your balance inside the protocol&apos;s Vault ledger — separate from your
            wallet&apos;s nUSD balance and separate from any LP shares you hold above.
          </p>
        </section>
      )}
    </div>
  );
}