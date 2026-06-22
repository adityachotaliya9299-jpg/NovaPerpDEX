"use client";

import { useEffect, useState } from "react";
import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/lib/contracts";
import { formatAmount, wadToNumber } from "@/lib/utils/format";
import { fetchLeaderboard, type SubgraphTraderVolume } from "@/lib/subgraph";
import { useToast, decodeRevertReason } from "@/components/Toast";

function timeAgo(unixSeconds: number): string {
  const diff = Math.floor(Date.now() / 1000) - unixSeconds;
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

function ClaimPanel() {
  const { address } = useAccount();
  const { show } = useToast();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { data } = useReadContracts({
    contracts: [
      { ...contracts.rewardDistributor, functionName: "stakedOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.rewardDistributor, functionName: "earned", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.rewardDistributor, functionName: "rewardRate" },
      { ...contracts.rewardDistributor, functionName: "totalStaked" },
      { ...contracts.rewardDistributor, functionName: "unallocatedRewards" },
      { ...contracts.lpVault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
    ] as any[],
    query: { enabled: !!address, refetchInterval: 10_000 },
  }) as { data: { result?: unknown }[] | undefined };

  const stakedOf = (data?.[0]?.result as bigint | undefined) ?? 0n;
  const earned = (data?.[1]?.result as bigint | undefined) ?? 0n;
  const rewardRate = (data?.[2]?.result as bigint | undefined) ?? 0n;
  const totalStaked = (data?.[3]?.result as bigint | undefined) ?? 0n;
  const unallocated = (data?.[4]?.result as bigint | undefined) ?? 0n;
  const lpBalance = (data?.[5]?.result as bigint | undefined) ?? 0n;

  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => { if (writeData) setTxHash(writeData); }, [writeData]);
  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      show("success", "Claimed", "nRWD rewards sent to your wallet.");
    }
  }, [isSuccess, show]);
  useEffect(() => {
    if (writeError) show("error", "Claim failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Claim reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);

  const isLoading = isPending || isConfirming;

  // Estimated daily emission from current rate
  const dailyEmission = wadToNumber(rewardRate) * 86400;

  // My share of rewards if I had all my LP staked
  const myShare = wadToNumber(totalStaked) > 0
    ? (wadToNumber(stakedOf) / wadToNumber(totalStaked)) * 100
    : 0;

  return (
    <div className="space-y-6">
      {/* Emission stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>Daily Emission</div>
          <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: "var(--accent-long)" }}>
            {dailyEmission.toFixed(2)} nRWD
          </div>
        </div>
        <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>Total Staked</div>
          <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: "var(--text-primary)" }}>
            {formatAmount(totalStaked, 4)} shares
          </div>
        </div>
        <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>Unallocated Reserve</div>
          <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: "var(--text-primary)" }}>
            {formatAmount(unallocated, 2)} nRWD
          </div>
        </div>
        <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <div className="text-xs mb-1.5" style={{ color: "var(--text-muted)" }}>Your Pool Share</div>
          <div className="font-mono text-lg tabular-nums font-semibold" style={{ color: "var(--accent-info)" }}>
            {myShare.toFixed(2)}%
          </div>
        </div>
      </div>

      {/* Personal staking + claim */}
      {address ? (
        <div className="border p-5 space-y-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <h3 className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
            Your Position
          </h3>
          <div className="grid grid-cols-3 gap-4 text-xs">
            <div>
              <div style={{ color: "var(--text-muted)" }} className="mb-1">LP shares staked</div>
              <div className="font-mono tabular-nums text-sm" style={{ color: "var(--text-primary)" }}>
                {formatAmount(stakedOf, 6)}
              </div>
            </div>
            <div>
              <div style={{ color: "var(--text-muted)" }} className="mb-1">LP shares available to stake</div>
              <div className="font-mono tabular-nums text-sm" style={{ color: "var(--text-primary)" }}>
                {formatAmount(lpBalance, 6)}
              </div>
            </div>
            <div>
              <div style={{ color: "var(--text-muted)" }} className="mb-1">Claimable nRWD</div>
              <div className="font-mono tabular-nums text-sm font-semibold" style={{ color: earned > 0n ? "var(--accent-long)" : "var(--text-muted)" }}>
                {formatAmount(earned, 6)}
              </div>
            </div>
          </div>

          <button
            onClick={() => writeContract({ ...contracts.rewardDistributor, functionName: "claim" })}
            disabled={isLoading || earned === 0n}
            className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
            style={{ background: "var(--accent-long)", color: "var(--bg-base)" }}
          >
            {isLoading ? (isConfirming ? "Confirming…" : "Sending…") : earned > 0n ? `Claim ${formatAmount(earned, 4)} nRWD` : "No rewards to claim"}
          </button>

          <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
            Stake LP shares via the Vaults page to start earning nRWD emissions. Rewards accrue
            continuously and are claimable at any time. Staking does not lock your LP position —
            you can unstake at any time with no cooldown.
          </p>
        </div>
      ) : (
        <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
          <p className="text-sm" style={{ color: "var(--text-muted)" }}>Connect wallet to view your rewards.</p>
        </div>
      )}
    </div>
  );
}

function Leaderboard() {
  const { address } = useAccount();
  const [rows, setRows] = useState<SubgraphTraderVolume[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchLeaderboard()
      .then((data) => { if (!cancelled) setRows(data); })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : String(e)); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);

  if (loading) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Loading leaderboard…</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--accent-short)" }}>Failed to load leaderboard: {error}</p>
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>No trades yet</p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>
          The leaderboard populates as traders open and close positions.
        </p>
      </div>
    );
  }

  return (
    <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
        <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Volume Leaderboard — All Time
        </span>
      </div>
      {rows.map((row, i) => {
        const isMe = !!address && row.account.toLowerCase() === address.toLowerCase();
        const medal = i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `#${i + 1}`;
        return (
          <div
            key={row.id}
            className="px-4 py-3 border-b last:border-b-0 flex items-center justify-between"
            style={{
              borderColor: "var(--border)",
              background: isMe ? "var(--bg-elevated)" : "transparent",
            }}
          >
            <div className="flex items-center gap-4 text-xs">
              <span className="w-8 text-center font-semibold" style={{ color: i < 3 ? "var(--text-primary)" : "var(--text-muted)" }}>
                {medal}
              </span>
              <div>
                <span
                  className="font-mono"
                  style={{ color: isMe ? "var(--accent-info)" : "var(--text-primary)" }}
                >
                  {row.account.slice(0, 6)}…{row.account.slice(-4)}
                  {isMe && <span className="ml-1.5 text-[10px]" style={{ color: "var(--accent-info)" }}>YOU</span>}
                </span>
                <div style={{ color: "var(--text-muted)" }} className="text-[10px] mt-0.5">
                  {row.tradeCount} trade{row.tradeCount !== 1 ? "s" : ""} · last {timeAgo(Number(row.lastTradeAt))}
                </div>
              </div>
            </div>
            <span className="font-mono text-sm tabular-nums font-semibold" style={{ color: "var(--text-primary)" }}>
              ${formatAmount(BigInt(row.totalVolume))}
            </span>
          </div>
        );
      })}
    </div>
  );
}

export function RewardsHub() {
  return (
    <div className="space-y-8">
      <ClaimPanel />
      <section>
        <h2 className="text-sm font-semibold mb-3" style={{ color: "var(--text-primary)" }}>
          Volume Leaderboard
        </h2>
        <p className="text-xs mb-4" style={{ color: "var(--text-muted)" }}>
          Ranked by total notional trading volume across all markets, all time.
          Volume counts both opens and closes — a $100 position opened then closed
          contributes $200 to the total. Sourced from the on-chain subgraph indexer,
          not self-reported.
        </p>
        <Leaderboard />
      </section>
    </div>
  );
}