"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/lib/contracts";
import { formatAmount, parseWad, wadToNumber } from "@/lib/utils/format";
import { useToast, decodeRevertReason } from "@/components/Toast";

const MAX_UINT256 = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

type Mode = "deposit" | "withdraw";

export function LPVaultPanel({ onChanged }: { onChanged?: () => void }) {
  const { address } = useAccount();
  const [mode, setMode] = useState<Mode>("deposit");
  const [amountInput, setAmountInput] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { data: reads, refetch: refetchReads } = useReadContracts({
    contracts: [
      { ...contracts.lpVault, functionName: "sharePrice" },
      { ...contracts.lpVault, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.collateralToken, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
      { ...contracts.collateralToken, functionName: "allowance", args: [address ?? "0x0000000000000000000000000000000000000000", contracts.lpVault.address] },
      { ...contracts.lpVault, functionName: "totalSupply" },
      { ...contracts.lpVault, functionName: "MIN_FIRST_DEPOSIT" },
    ],
    query: { enabled: !!address, refetchInterval: 12_000 },
  });

  const sharePrice = (reads?.[0]?.result as bigint | undefined) ?? 0n;
  const lpBalance = (reads?.[1]?.result as bigint | undefined) ?? 0n;
  const walletBalance = (reads?.[2]?.result as bigint | undefined) ?? 0n;
  const allowance = (reads?.[3]?.result as bigint | undefined) ?? 0n;
  const totalSupply = (reads?.[4]?.result as bigint | undefined) ?? 0n;
  const minFirstDeposit = (reads?.[5]?.result as bigint | undefined) ?? 0n;
  const isFirstDeposit = totalSupply === 0n;

  const amount = parseWad(amountInput);

  // For deposit, `amount` is in assets (nUSD). For withdraw, `amount` is in
  // shares — LPVault.withdraw(shares) takes shares, not assets, despite the
  // name. previewRedeem converts shares -> assets for the preview line.
  const { data: preview } = useReadContract({
    ...contracts.lpVault,
    functionName: mode === "deposit" ? "previewDeposit" : "previewRedeem",
    args: [amount],
    query: { enabled: amount > 0n },
  });

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
      show(
        "success",
        mode === "deposit" ? "Deposited" : "Withdrawn",
        mode === "deposit"
          ? `$${formatAmount(amount)} added to the LP vault.`
          : `${formatAmount(amount, 6)} shares redeemed.`
      );
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

  const needsApproval = mode === "deposit" && (!allowance || allowance < amount);
  const isLoading = isPending || isConfirming;

  function handleApprove() {
    writeContract({
      ...contracts.collateralToken,
      functionName: "approve",
      args: [contracts.lpVault.address, MAX_UINT256],
    });
  }

  function handleDeposit() {
    if (amount === 0n) return;
    writeContract({ ...contracts.lpVault, functionName: "deposit", args: [amount] });
  }

  function handleWithdraw() {
    if (amount === 0n) return;
    writeContract({ ...contracts.lpVault, functionName: "withdraw", args: [amount] });
  }

  const yourValue = sharePrice > 0n ? (wadToNumber(lpBalance) * wadToNumber(sharePrice)) : 0;

  return (
    <div className="border p-4 space-y-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="flex border-b" style={{ borderColor: "var(--border)" }}>
        {(["deposit", "withdraw"] as Mode[]).map((m) => (
          <button
            key={m}
            onClick={() => {
              setMode(m);
              setAmountInput("");
            }}
            className="flex-1 py-2.5 text-sm font-medium capitalize transition-colors"
            style={{
              color: mode === m ? "var(--text-primary)" : "var(--text-muted)",
              borderBottom: mode === m ? "2px solid var(--accent-info)" : "2px solid transparent",
            }}
          >
            {m}
          </button>
        ))}
      </div>

      {address && (
        <div className="flex justify-between text-xs px-1" style={{ color: "var(--text-muted)" }}>
          <span>Your LP position</span>
          <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
            ${yourValue.toFixed(2)}
          </span>
        </div>
      )}

      {isFirstDeposit && mode === "deposit" && (
        <p className="text-[11px] px-1" style={{ color: "var(--accent-warn)" }}>
          The vault is empty — the first deposit must be at least $
          {formatAmount(minFirstDeposit)} (anti-inflation-attack floor).
        </p>
      )}

      <div>
        <div className="flex items-center justify-between mb-1.5">
          <label className="text-xs" style={{ color: "var(--text-muted)" }}>
            {mode === "deposit" ? "Amount (nUSD)" : "Shares to redeem"}
          </label>
          <button
            className="text-xs"
            style={{ color: "var(--accent-info)" }}
            onClick={() =>
              setAmountInput(
                mode === "deposit"
                  ? (Number(walletBalance) / 1e18).toFixed(2)
                  : (Number(lpBalance) / 1e18).toFixed(6)
              )
            }
          >
            MAX
          </button>
        </div>
        <input
          type="number"
          min="0"
          placeholder="0.00"
          value={amountInput}
          onChange={(e) => setAmountInput(e.target.value)}
          className="w-full bg-transparent border px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
          style={{ borderColor: "var(--border)", background: "var(--bg-elevated)", color: "var(--text-primary)" }}
        />
      </div>

      {preview !== undefined && amount > 0n && (
        <div className="text-xs flex justify-between px-1" style={{ color: "var(--text-muted)" }}>
          <span>You&apos;ll receive</span>
          <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
            {mode === "deposit" ? `${formatAmount(preview as bigint, 6)} shares` : `$${formatAmount(preview as bigint)}`}
          </span>
        </div>
      )}

      {!address ? (
        <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
          Connect wallet to provide liquidity
        </p>
      ) : mode === "deposit" && needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={isLoading}
          className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-50"
          style={{ background: "var(--bg-elevated)", color: "var(--text-primary)", border: "1px solid var(--border)" }}
        >
          {isLoading ? "Approving…" : "Approve nUSD"}
        </button>
      ) : (
        <button
          onClick={mode === "deposit" ? handleDeposit : handleWithdraw}
          disabled={isLoading || amount === 0n}
          className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
          style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
        >
          {isLoading
            ? isConfirming ? "Confirming…" : "Sending…"
            : mode === "deposit" ? "Deposit" : "Withdraw"}
        </button>
      )}
    </div>
  );
}