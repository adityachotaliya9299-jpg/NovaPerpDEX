"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/lib/contracts";
import { formatAmount, parseWad } from "@/lib/utils/format";
import { useToast, decodeRevertReason } from "@/components/Toast";

const MAX_UINT256 = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

type Mode = "stake" | "unstake";

export function StakingPanel({ onChanged }: { onChanged?: () => void }) {
  const { address } = useAccount();
  const [mode, setMode] = useState<Mode>("stake");
  const [amountInput, setAmountInput] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { data: reads, refetch: refetchReads } = useReadContracts({
    contracts: [
      { ...contracts.lpVault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.lpVault, functionName: "allowance", args: [address ?? "0x0000000000000000000000000000000000000000", contracts.rewardDistributor.address] },
      { ...contracts.rewardDistributor, functionName: "stakedOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.rewardDistributor, functionName: "earned", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.rewardDistributor, functionName: "totalStaked" },
      { ...contracts.rewardDistributor, functionName: "rewardRate" },
    ],
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  const lpBalance = (reads?.[0]?.result as bigint | undefined) ?? 0n;
  const allowance = (reads?.[1]?.result as bigint | undefined) ?? 0n;
  const stakedBalance = (reads?.[2]?.result as bigint | undefined) ?? 0n;
  const earned = (reads?.[3]?.result as bigint | undefined) ?? 0n;
  const totalStaked = (reads?.[4]?.result as bigint | undefined) ?? 0n;
  const rewardRate = (reads?.[5]?.result as bigint | undefined) ?? 0n;

  const amount = parseWad(amountInput);
  const needsApproval = mode === "stake" && (!allowance || allowance < amount);

  const { show } = useToast();
  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (writeData) setTxHash(writeData);
  }, [writeData]);

  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      if (lastAction === "claim") {
        show("success", "Claimed", "nRWD rewards sent to your wallet.");
      } else {
        show(
          "success",
          lastAction === "stake" ? "Staked" : "Unstaked",
          `${formatAmount(amount, 6)} LP shares ${lastAction === "stake" ? "now earning nRWD" : "returned to your balance"}.`
        );
      }
      setAmountInput("");
      refetchReads();
      onChanged?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess, refetchReads, onChanged]);

  useEffect(() => {
    if (writeError) show("error", "Action failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Action reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);

  const isLoading = isPending || isConfirming;

  const [lastAction, setLastAction] = useState<Mode | "claim" | null>(null);
  function handleApprove() {
    writeContract({
      ...contracts.lpVault,
      functionName: "approve",
      args: [contracts.rewardDistributor.address, MAX_UINT256],
    });
  }
  function handleStake() {
    if (amount === 0n) return;
    setLastAction("stake");
    writeContract({ ...contracts.rewardDistributor, functionName: "stake", args: [amount] });
  }
  function handleUnstake() {
    if (amount === 0n) return;
    setLastAction("unstake");
    writeContract({ ...contracts.rewardDistributor, functionName: "unstake", args: [amount] });
  }
  function handleClaim() {
    setLastAction("claim");
    writeContract({ ...contracts.rewardDistributor, functionName: "claim", args: [] });
  }

  return (
    <div className="border p-4 space-y-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <h3 className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
        Stake LP Shares — Earn nRWD
      </h3>

      {address && (
        <div className="grid grid-cols-2 gap-3 text-xs">
          <div>
            <div style={{ color: "var(--text-muted)" }} className="mb-0.5">Staked</div>
            <div className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
              {formatAmount(stakedBalance, 6)}
            </div>
          </div>
          <div>
            <div style={{ color: "var(--text-muted)" }} className="mb-0.5">Earned</div>
            <div className="font-mono tabular-nums" style={{ color: "var(--accent-long)" }}>
              {formatAmount(earned, 6)} nRWD
            </div>
          </div>
        </div>
      )}

      {address && earned > 0n && (
        <button
          onClick={handleClaim}
          disabled={isLoading}
          className="w-full py-2 text-xs font-semibold transition-opacity disabled:opacity-50"
          style={{ background: "var(--accent-long)", color: "var(--bg-base)" }}
        >
          Claim {formatAmount(earned, 6)} nRWD
        </button>
      )}

      <div className="flex border-b" style={{ borderColor: "var(--border)" }}>
        {(["stake", "unstake"] as Mode[]).map((m) => (
          <button
            key={m}
            onClick={() => {
              setMode(m);
              setAmountInput("");
            }}
            className="flex-1 py-2 text-sm font-medium capitalize transition-colors"
            style={{
              color: mode === m ? "var(--text-primary)" : "var(--text-muted)",
              borderBottom: mode === m ? "2px solid var(--accent-info)" : "2px solid transparent",
            }}
          >
            {m}
          </button>
        ))}
      </div>

      <div>
        <div className="flex items-center justify-between mb-1.5">
          <label className="text-xs" style={{ color: "var(--text-muted)" }}>
            LP shares
          </label>
          <button
            className="text-xs"
            style={{ color: "var(--accent-info)" }}
            onClick={() =>
              setAmountInput(
                mode === "stake"
                  ? (Number(lpBalance) / 1e18).toFixed(6)
                  : (Number(stakedBalance) / 1e18).toFixed(6)
              )
            }
          >
            MAX
          </button>
        </div>
        <input
          type="number"
          min="0"
          placeholder="0.000000"
          value={amountInput}
          onChange={(e) => setAmountInput(e.target.value)}
          className="w-full bg-transparent border px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
          style={{ borderColor: "var(--border)", background: "var(--bg-elevated)", color: "var(--text-primary)" }}
        />
      </div>

      {!address ? (
        <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
          Connect wallet to stake
        </p>
      ) : needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={isLoading}
          className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-50"
          style={{ background: "var(--bg-elevated)", color: "var(--text-primary)", border: "1px solid var(--border)" }}
        >
          {isLoading ? "Approving…" : "Approve LP shares"}
        </button>
      ) : (
        <button
          onClick={mode === "stake" ? handleStake : handleUnstake}
          disabled={isLoading || amount === 0n}
          className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
          style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
        >
          {isLoading
            ? isConfirming ? "Confirming…" : "Sending…"
            : mode === "stake" ? "Stake" : "Unstake"}
        </button>
      )}

      <div className="text-[11px] flex justify-between px-1" style={{ color: "var(--text-muted)" }}>
        <span>Total staked (all LPs)</span>
        <span className="font-mono tabular-nums">{formatAmount(totalStaked, 6)} shares</span>
      </div>
      <div className="text-[11px] flex justify-between px-1" style={{ color: "var(--text-muted)" }}>
        <span>Emission status</span>
        <span className="font-mono tabular-nums" style={{ color: rewardRate > 0n ? "var(--accent-long)" : "var(--text-muted)" }}>
          {rewardRate > 0n ? "active" : "no active emission"}
        </span>
      </div>
    </div>
  );
}