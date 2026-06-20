"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/lib/contracts";

const FAUCET_AMOUNT = 10_000n * 10n ** 18n; // 10,000 nUSD per claim
const COOLDOWN_MS = 24 * 60 * 60 * 1000; // 24h cooldown (client-side only)

export function Faucet() {
  const { address } = useAccount();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const [lastClaim, setLastClaim] = useState<number>(0);

  // Key the cooldown to the token contract address, not a fixed string —
  // otherwise a fresh deployment (new MockUSD address) inherits a stale
  // cooldown from localStorage and the faucet button looks broken/disabled
  // even though the wallet has zero balance on the new contracts. This bit
  // us directly during the v2 Chainlink redeploy.
  const storageKey = `novaperp_faucet_last_claim_${contracts.collateralToken.address}`;

  const { data: balance, refetch: refetchBalance } = useReadContract({
    ...contracts.collateralToken,
    functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  const { writeContract, data: writeData, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (writeData) setTxHash(writeData);
  }, [writeData]);

  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      refetchBalance();
      const now = Date.now();
      localStorage.setItem(storageKey, String(now));
      setLastClaim(now);
    }
  }, [isSuccess, refetchBalance, storageKey]);

  useEffect(() => {
    const stored = localStorage.getItem(storageKey);
    if (stored) setLastClaim(Number(stored));
    else setLastClaim(0);
  }, [storageKey]);

  const balanceFormatted = balance
    ? (Number(balance) / 1e18).toLocaleString("en-US", { maximumFractionDigits: 2 })
    : "—";

  const cooldownRemaining = Math.max(0, COOLDOWN_MS - (Date.now() - lastClaim));
  const onCooldown = cooldownRemaining > 0;
  const hoursLeft = Math.ceil(cooldownRemaining / (1000 * 60 * 60));

  const isLoading = isPending || isConfirming;

  function handleClaim() {
    if (!address || onCooldown) return;
    writeContract({
      ...contracts.collateralToken,
      functionName: "mint",
      args: [address, FAUCET_AMOUNT],
    });
  }

  if (!address) return null;

  return (
    <div
      className="flex items-center gap-3 px-3 py-1.5 border text-xs"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      <div style={{ color: "var(--text-muted)" }}>
        nUSD:{" "}
        <span className="font-mono font-semibold" style={{ color: "var(--text-primary)" }}>
          {balanceFormatted}
        </span>
      </div>

      <button
        onClick={handleClaim}
        disabled={isLoading || onCooldown}
        className="px-2.5 py-1 text-[11px] font-semibold transition-opacity disabled:opacity-40"
        style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
        title={onCooldown ? `Available again in ${hoursLeft}h` : "Claim 10,000 nUSD"}
      >
        {isLoading
          ? isConfirming ? "Confirming…" : "Sending…"
          : onCooldown
          ? `Faucet (${hoursLeft}h)`
          : "Get nUSD"}
      </button>

      {txHash && (
        <a
          href={`https://sepolia.etherscan.io/tx/${txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-[10px]"
          style={{ color: "var(--accent-info)" }}
        >
          ↗ tx
        </a>
      )}
    </div>
  );
}