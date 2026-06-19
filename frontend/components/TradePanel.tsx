"use client";

import { useState, useEffect, useCallback } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { parseWad, SIDE, type Side } from "@/lib/utils/format";

type Tab = "open" | "close";

const MAX_UINT256 = BigInt(
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
);

export function TradePanel({ onTraded }: { onTraded?: () => void }) {
  const { address } = useAccount();
  const [tab, setTab] = useState<Tab>("open");
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [sizeInput, setSizeInput] = useState("");
  const [collateralInput, setCollateralInput] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const size = parseWad(sizeInput);
  const collateral = parseWad(collateralInput);

  // ---- reads ----
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    ...contracts.collateralToken,
    functionName: "allowance",
    args: [
      address ?? "0x0000000000000000000000000000000000000000",
      contracts.collateralVault.address,
    ],
    query: { enabled: !!address },
  });

  const { data: balance } = useReadContract({
    ...contracts.collateralToken,
    functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

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
      setSizeInput("");
      setCollateralInput("");
      setTxHash(undefined);
      refetchAllowance();
      onTraded?.();
    }
  }, [isSuccess, refetchAllowance, onTraded]);

  // ---- derived state ----
  const needsApproval = !allowance || (collateral > 0n && allowance < collateral);
  const hasPosition =
    side === SIDE.LONG
      ? ((longPos as { size: bigint } | undefined)?.size ?? 0n) > 0n
      : ((shortPos as { size: bigint } | undefined)?.size ?? 0n) > 0n;

  // ---- handlers ----
  // NOTE: increasePosition and closePosition go through PositionRouter,
  // NOT MarginManager directly. MarginManager.increasePosition has an
  // onlyRouter modifier — direct wallet calls revert. PositionRouter is
  // whitelisted as an approved router in Deploy.s.sol Phase 5 via
  // mm.setRouter(address(router), true).
  const handleApprove = useCallback(() => {
    writeContract({
      ...contracts.collateralToken,
      functionName: "approve",
      args: [contracts.collateralVault.address, MAX_UINT256],
    });
  }, [writeContract]);

  const handleOpen = useCallback(() => {
    if (!address || size === 0n || collateral === 0n) return;
    writeContract({
      ...contracts.positionRouter,
      functionName: "increasePosition",
      args: [ETH_USD_MARKET, side, size, collateral],
    });
  }, [address, size, collateral, side, writeContract]);

  const handleClose = useCallback(() => {
    if (!address) return;
    writeContract({
      ...contracts.positionRouter,
      functionName: "closePosition",
      args: [ETH_USD_MARKET, side],
    });
  }, [address, side, writeContract]);

  // ---- helpers ----
  const isLoading = isWritePending || isConfirming;
  const balanceFl = balance ? (Number(balance) / 1e18).toFixed(2) : "—";
  const leveragePreview =
    size > 0n && collateral > 0n
      ? (Number(size) / Number(collateral)).toFixed(1)
      : null;

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
              <label
                className="text-xs mb-1.5 block"
                style={{ color: "var(--text-muted)" }}
              >
                Position size (nUSD)
              </label>
              <div
                className="flex items-center border"
                style={{
                  borderColor: "var(--border)",
                  background: "var(--bg-elevated)",
                }}
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
                <span className="px-3 text-xs" style={{ color: "var(--text-muted)" }}>
                  nUSD
                </span>
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
                    balance &&
                    setCollateralInput((Number(balance) / 1e18).toFixed(2))
                  }
                >
                  MAX {balanceFl}
                </button>
              </div>
              <div
                className="flex items-center border"
                style={{
                  borderColor: "var(--border)",
                  background: "var(--bg-elevated)",
                }}
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
                <span className="px-3 text-xs" style={{ color: "var(--text-muted)" }}>
                  nUSD
                </span>
              </div>
            </div>

            {/* Leverage preview */}
            {leveragePreview && (
              <div
                className="flex justify-between text-xs px-1"
                style={{ color: "var(--text-muted)" }}
              >
                <span>Leverage</span>
                <span
                  className="font-mono tabular-nums"
                  style={{ color: "var(--text-primary)" }}
                >
                  {leveragePreview}x
                </span>
              </div>
            )}

            {/* CTA */}
            {!address ? (
              <p
                className="text-xs text-center py-2"
                style={{ color: "var(--text-muted)" }}
              >
                Connect wallet to trade
              </p>
            ) : needsApproval ? (
              <button
                onClick={handleApprove}
                disabled={isLoading}
                className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-50"
                style={btnNeutral}
              >
                {isLoading ? "Approving…" : "Approve nUSD"}
              </button>
            ) : (
              <button
                onClick={handleOpen}
                disabled={isLoading || size === 0n || collateral === 0n}
                className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
                style={side === SIDE.LONG ? btnLong : btnShort}
              >
                {isLoading
                  ? isConfirming
                    ? "Confirming…"
                    : "Sending…"
                  : `Open ${side === SIDE.LONG ? "Long" : "Short"}`}
              </button>
            )}
          </>
        ) : (
          /* Close tab */
          <div className="space-y-3">
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              Closes your entire {side === SIDE.LONG ? "long" : "short"} position at
              the current mark price.
            </p>
            {!address ? (
              <p
                className="text-xs text-center py-2"
                style={{ color: "var(--text-muted)" }}
              >
                Connect wallet to trade
              </p>
            ) : !hasPosition ? (
              <p
                className="text-xs text-center py-3"
                style={{ color: "var(--text-muted)" }}
              >
                No open {side === SIDE.LONG ? "long" : "short"} position
              </p>
            ) : (
              <button
                onClick={handleClose}
                disabled={isLoading}
                className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-50"
                style={side === SIDE.LONG ? btnLong : btnShort}
              >
                {isLoading
                  ? isConfirming
                    ? "Confirming…"
                    : "Sending…"
                  : `Close ${side === SIDE.LONG ? "Long" : "Short"}`}
              </button>
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