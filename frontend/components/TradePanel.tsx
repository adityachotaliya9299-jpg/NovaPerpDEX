"use client";

import { useState, useEffect, useCallback } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { parseWad, formatAmount, SIDE, type Side } from "@/lib/utils/format";

type Tab = "open" | "close";

/**
 * How collateral works in NovaPerpDEX (differs from a naive ERC20-approve flow):
 *
 * The protocol has a `Vault` contract that acts as an internal accounting layer.
 * Users must first deposit nUSD into Vault (getting a "free" balance), then
 * PositionRouter.increasePosition moves that free balance to "locked" when
 * opening a position. Withdrawing after closing moves it back to "free", then
 * Vault.withdraw() returns nUSD to the wallet.
 *
 * Full open flow:
 *   1. nUSD.approve(Vault, MAX)               — one time
 *   2. Vault.deposit(collateral + fee buffer) — moves nUSD wallet → Vault free balance
 *   3. PositionRouter.increasePosition()      — Vault free → locked, position opens
 *
 * Full close flow:
 *   1. PositionRouter.closePosition()    — position closes, collateral+PnL → Vault free
 *   2. Vault.withdraw(amount)            — Vault free balance → nUSD wallet
 *
 * This is why "Approve nUSD → CollateralVault" was wrong and caused
 * Vault.InsufficientFree revert: CollateralVault never receives ERC20 directly;
 * it only moves balances already inside Vault.
 *
 * IMPORTANT: depositing exactly `collateral` is also wrong and causes a
 * second, subtler Vault.InsufficientFree revert — MarginManager charges a
 * position fee (POSITION_FEE_BPS in Deploy.s.sol, 0.1% of size) out of the
 * LOCKED amount when opening, so Vault needs collateral + fee sitting free,
 * not just collateral. See depositAmount below.
 */

const MAX_UINT256 = BigInt(
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
);

type Step = "approve" | "deposit" | "open" | "close" | "withdraw";

export function TradePanel({ onTraded }: { onTraded?: () => void }) {
  const { address } = useAccount();
  const [tab, setTab] = useState<Tab>("open");
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [sizeInput, setSizeInput] = useState("");
  const [collateralInput, setCollateralInput] = useState("");
  const [pendingStep, setPendingStep] = useState<Step | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const size = parseWad(sizeInput);
  const collateral = parseWad(collateralInput);

  // PositionRouter -> MarginManager charges a position fee (0.1% = 10 bps of
  // size, per Deploy.s.sol's POSITION_FEE_BPS) out of the LOCKED amount when
  // opening. Vault.deposit must therefore cover collateral + fee, or
  // increasePosition reverts with Vault.InsufficientFree (locking needs more
  // than what's free). We pad with a small safety margin on top of the exact
  // fee calc in case of any rounding differences between this estimate and
  // the contract's own fee math.
  const POSITION_FEE_BPS = 10n; // 0.1%, matches deploy script
  const estimatedFee = (size * POSITION_FEE_BPS) / 10_000n;
  const FEE_SAFETY_MARGIN = (collateral * 5n) / 10_000n; // +0.05% buffer
  const depositAmount = collateral + estimatedFee + FEE_SAFETY_MARGIN;

  // ---- reads ----
  const { data: reads, refetch: refetchReads } = useReadContracts({
    contracts: [
      // [0] nUSD allowance to Vault
      {
        ...contracts.collateralToken,
        functionName: "allowance",
        args: [
          address ?? "0x0000000000000000000000000000000000000000",
          contracts.vault.address,
        ],
      },
      // [1] nUSD wallet balance
      {
        ...contracts.collateralToken,
        functionName: "balanceOf",
        args: [address ?? "0x0000000000000000000000000000000000000000"],
      },
      // [2] Vault free balance (deposited but not yet in a position)
      {
        ...contracts.vault,
        functionName: "balanceOf",
        args: [address ?? "0x0000000000000000000000000000000000000000"],
      },
    ],
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  const allowance = (reads?.[0]?.result as bigint | undefined) ?? 0n;
  const walletBalance = (reads?.[1]?.result as bigint | undefined) ?? 0n;
  const vaultBalance = (reads?.[2]?.result as bigint | undefined) ?? 0n;

  // Position reads (only when on close tab)
  const { data: longPos } = useReadContract({
    ...contracts.marginManager,
    functionName: "getPosition",
    args: [
      address ?? "0x0000000000000000000000000000000000000000",
      ETH_USD_MARKET,
      SIDE.LONG,
    ],
    query: { enabled: !!address && tab === "close" },
  });

  const { data: shortPos } = useReadContract({
    ...contracts.marginManager,
    functionName: "getPosition",
    args: [
      address ?? "0x0000000000000000000000000000000000000000",
      ETH_USD_MARKET,
      SIDE.SHORT,
    ],
    query: { enabled: !!address && tab === "close" },
  });

  // ---- writes ----
  const { writeContract, data: writeData, isPending: isWritePending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (writeData) setTxHash(writeData);
  }, [writeData]);

  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      refetchReads();

      // Multi-step flow: after each step, advance to the next
      if (pendingStep === "approve") {
        // Approved — now deposit (collateral + fee buffer, see note above)
        setPendingStep("deposit");
        writeContract({
          ...contracts.vault,
          functionName: "deposit",
          args: [depositAmount],
        });
      } else if (pendingStep === "deposit") {
        // Deposited — now open position
        setPendingStep("open");
        writeContract({
          ...contracts.positionRouter,
          functionName: "increasePosition",
          args: [ETH_USD_MARKET, side, size, collateral],
        });
      } else if (pendingStep === "open") {
        // Position opened — done
        setPendingStep(null);
        setSizeInput("");
        setCollateralInput("");
        onTraded?.();
      } else if (pendingStep === "close") {
        // Position closed — now withdraw collateral from Vault
        // Withdraw whatever is now free in the vault
        setPendingStep("withdraw");
        writeContract({
          ...contracts.vault,
          functionName: "withdraw",
          args: [vaultBalance],
        });
      } else if (pendingStep === "withdraw") {
        // Withdrawn — done
        setPendingStep(null);
        onTraded?.();
      } else {
        setPendingStep(null);
        onTraded?.();
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess]);

  // ---- derived state ----
  const needsApproval = !allowance || allowance < depositAmount;
  const hasPosition =
    side === SIDE.LONG
      ? ((longPos as { size: bigint } | undefined)?.size ?? 0n) > 0n
      : ((shortPos as { size: bigint } | undefined)?.size ?? 0n) > 0n;

  // ---- handlers ----
  const handleOpen = useCallback(() => {
    if (!address || size === 0n || collateral === 0n) return;

    if (needsApproval) {
      // Step 1: approve, then deposit, then open (chained in useEffect above)
      setPendingStep("approve");
      writeContract({
        ...contracts.collateralToken,
        functionName: "approve",
        args: [contracts.vault.address, MAX_UINT256],
      });
    } else if (vaultBalance < depositAmount) {
      // Step 2: deposit first, then open (collateral + fee buffer)
      setPendingStep("deposit");
      writeContract({
        ...contracts.vault,
        functionName: "deposit",
        args: [depositAmount],
      });
    } else {
      // Vault already has enough free balance — open directly
      setPendingStep("open");
      writeContract({
        ...contracts.positionRouter,
        functionName: "increasePosition",
        args: [ETH_USD_MARKET, side, size, collateral],
      });
    }
  }, [address, size, collateral, depositAmount, side, needsApproval, vaultBalance, writeContract]);

  const handleClose = useCallback(() => {
    if (!address) return;
    setPendingStep("close");
    writeContract({
      ...contracts.positionRouter,
      functionName: "closePosition",
      args: [ETH_USD_MARKET, side],
    });
  }, [address, side, writeContract]);

  // ---- helpers ----
  const isLoading = isWritePending || isConfirming || pendingStep !== null;

  const walletBalanceFl = (Number(walletBalance) / 1e18).toFixed(2);
  const vaultBalanceFl = (Number(vaultBalance) / 1e18).toFixed(2);
  const leveragePreview =
    size > 0n && collateral > 0n
      ? (Number(size) / Number(collateral)).toFixed(1)
      : null;

  function stepLabel(): string {
    if (!isLoading) return "";
    if (isConfirming) {
      if (pendingStep === "approve") return "Approving…";
      if (pendingStep === "deposit") return "Depositing to Vault…";
      if (pendingStep === "open") return "Opening position…";
      if (pendingStep === "close") return "Closing position…";
      if (pendingStep === "withdraw") return "Withdrawing from Vault…";
    }
    return "Sending…";
  }

  function openButtonLabel(): string {
    if (isLoading) return stepLabel();
    if (needsApproval) return `Approve & Open ${side === SIDE.LONG ? "Long" : "Short"}`;
    if (vaultBalance < depositAmount) return `Deposit & Open ${side === SIDE.LONG ? "Long" : "Short"}`;
    return `Open ${side === SIDE.LONG ? "Long" : "Short"}`;
  }

  const btnLong = { background: "var(--accent-long)", color: "var(--bg-base)" };
  const btnShort = { background: "var(--accent-short)", color: "#fff" };
  const btnNeutral = {
    background: "var(--bg-elevated)",
    color: "var(--text-primary)",
    border: "1px solid var(--border)",
  };

  return (
    <div
      className="border"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      {/* Tabs */}
      <div className="flex border-b" style={{ borderColor: "var(--border)" }}>
        {(["open", "close"] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="flex-1 py-3 text-sm font-medium capitalize transition-colors"
            style={{
              color: tab === t ? "var(--text-primary)" : "var(--text-muted)",
              borderBottom:
                tab === t ? "2px solid var(--accent-info)" : "2px solid transparent",
              background: "transparent",
            }}
          >
            {t} position
          </button>
        ))}
      </div>

      <div className="p-4 space-y-4">
        {/* Side selector */}
        <div className="flex gap-2">
          <button
            onClick={() => setSide(SIDE.LONG)}
            className="flex-1 py-2 text-sm font-semibold transition-opacity"
            style={
              side === SIDE.LONG ? btnLong : { ...btnNeutral, opacity: 0.55 }
            }
          >
            Long
          </button>
          <button
            onClick={() => setSide(SIDE.SHORT)}
            className="flex-1 py-2 text-sm font-semibold transition-opacity"
            style={
              side === SIDE.SHORT ? btnShort : { ...btnNeutral, opacity: 0.55 }
            }
          >
            Short
          </button>
        </div>

        {tab === "open" ? (
          <>
            {/* Size */}
            <div>
              <label className="text-xs mb-1.5 block" style={{ color: "var(--text-muted)" }}>
                Position size (nUSD)
              </label>
              <div
                className="flex items-center border"
                style={{ borderColor: "var(--border)", background: "var(--bg-elevated)" }}
              >
                <input
                  type="number"
                  min="0"
                  placeholder="0.00"
                  value={sizeInput}
                  onChange={(e) => setSizeInput(e.target.value)}
                  className="flex-1 bg-transparent px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
                  style={{ color: "var(--text-primary)" }}
                />
                <span className="px-3 text-xs" style={{ color: "var(--text-muted)" }}>nUSD</span>
              </div>
            </div>

            {/* Collateral */}
            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-xs" style={{ color: "var(--text-muted)" }}>
                  Collateral (nUSD)
                </label>
                <button
                  className="text-xs"
                  style={{ color: "var(--accent-info)" }}
                  onClick={() =>
                    setCollateralInput((Number(walletBalance) / 1e18).toFixed(2))
                  }
                >
                  MAX {walletBalanceFl}
                </button>
              </div>
              <div
                className="flex items-center border"
                style={{ borderColor: "var(--border)", background: "var(--bg-elevated)" }}
              >
                <input
                  type="number"
                  min="0"
                  placeholder="0.00"
                  value={collateralInput}
                  onChange={(e) => setCollateralInput(e.target.value)}
                  className="flex-1 bg-transparent px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
                  style={{ color: "var(--text-primary)" }}
                />
                <span className="px-3 text-xs" style={{ color: "var(--text-muted)" }}>nUSD</span>
              </div>
            </div>

            {/* Vault balance info */}
            {address && vaultBalance > 0n && (
              <div className="text-xs flex justify-between px-1" style={{ color: "var(--text-muted)" }}>
                <span>Trading collateral ready (separate from LP)</span>
                <span className="font-mono tabular-nums" style={{ color: "var(--accent-info)" }}>
                  ${vaultBalanceFl} ready
                </span>
              </div>
            )}

            {/* Leverage preview */}
            {leveragePreview && (
              <div className="flex justify-between text-xs px-1" style={{ color: "var(--text-muted)" }}>
                <span>Leverage</span>
                <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
                  {leveragePreview}x
                </span>
              </div>
            )}

            {/* Step indicator */}
            {address && collateral > 0n && !isLoading && (
              <div className="text-[11px] px-1 space-y-0.5" style={{ color: "var(--text-muted)" }}>
                {needsApproval && <div>① Approve nUSD → Vault</div>}
                {(needsApproval || vaultBalance < depositAmount) && <div>{needsApproval ? "②" : "①"} Deposit to Vault</div>}
                <div>{needsApproval ? "③" : vaultBalance < depositAmount ? "②" : "①"} Open position</div>
              </div>
            )}

            {!address ? (
              <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
                Connect wallet to trade
              </p>
            ) : (
              <button
                onClick={handleOpen}
                disabled={isLoading || size === 0n || collateral === 0n}
                className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
                style={side === SIDE.LONG ? btnLong : btnShort}
              >
                {openButtonLabel()}
              </button>
            )}
          </>
        ) : (
          /* Close tab */
          <div className="space-y-3">
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              Closes your {side === SIDE.LONG ? "long" : "short"} position and
              withdraws your collateral back to your wallet automatically.
            </p>
            {!address ? (
              <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
                Connect wallet to trade
              </p>
            ) : !hasPosition ? (
              <p className="text-xs text-center py-3" style={{ color: "var(--text-muted)" }}>
                No open {side === SIDE.LONG ? "long" : "short"} position
              </p>
            ) : (
              <>
                <div className="text-[11px] px-1 space-y-0.5" style={{ color: "var(--text-muted)" }}>
                  <div>① Close position → collateral returns to Vault</div>
                  <div>② Withdraw from Vault → nUSD back to wallet</div>
                </div>
                <button
                  onClick={handleClose}
                  disabled={isLoading}
                  className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-50"
                  style={side === SIDE.LONG ? btnLong : btnShort}
                >
                  {isLoading
                    ? stepLabel()
                    : `Close ${side === SIDE.LONG ? "Long" : "Short"} & Withdraw`}
                </button>
              </>
            )}
          </div>
        )}

        {/* Tx link */}
        {txHash && (
          <p className="text-xs text-center">
            <a
              href={`https://sepolia.etherscan.io/tx/${txHash}`}
              target="_blank"
              rel="noopener noreferrer"
              style={{ color: "var(--accent-info)" }}
            >
              {isConfirming ? "Waiting for confirmation…" : "View on Etherscan ↗"}
            </a>
          </p>
        )}
      </div>
    </div>
  );
}