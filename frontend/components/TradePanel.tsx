"use client";

import { useState, useEffect, useCallback } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { contracts } from "@/lib/contracts";
import { useMarket } from "@/lib/market-context";
import { parseWad, formatAmount, estimateLiqPrice, SIDE, type Side } from "@/lib/utils/format";
import { useToast, decodeRevertReason } from "@/components/Toast";

type Tab = "open" | "close";

const MAX_UINT256 = BigInt(
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
);
const MAINTENANCE_BPS = 200;
const MAX_LEVERAGE = 50;

type Step = "approve" | "deposit" | "open" | "close" | "withdraw";

export function TradePanel({ onTraded }: { onTraded?: () => void }) {
  const { address } = useAccount();
  const { activeMarket } = useMarket();
  const { show } = useToast();
  const [tab, setTab] = useState<Tab>("open");
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [collateralInput, setCollateralInput] = useState("");
  const [leverage, setLeverage] = useState(1);
  const [pendingStep, setPendingStep] = useState<Step | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const collateral = parseWad(collateralInput);
  const size = (collateral * BigInt(Math.round(leverage * 100))) / 100n;

  const POSITION_FEE_BPS = 10n;
  const estimatedFee = (size * POSITION_FEE_BPS) / 10_000n;
  const FEE_SAFETY_MARGIN = (collateral * 5n) / 10_000n;
  const depositAmount = collateral + estimatedFee + FEE_SAFETY_MARGIN;

  // Reset inputs when switching markets — a half-typed BTC order carried
  // over into an ETH tab (or vice versa) would be confusing and risks
  // submitting the wrong size against the wrong market.
  useEffect(() => {
    setCollateralInput("");
    setLeverage(1);
  }, [activeMarket.id]);

  const { data: reads, refetch: refetchReads } = useReadContracts({
    contracts: [
      {
        ...contracts.collateralToken,
        functionName: "allowance",
        args: [
          address ?? "0x0000000000000000000000000000000000000000",
          contracts.vault.address,
        ],
      },
      {
        ...contracts.collateralToken,
        functionName: "balanceOf",
        args: [address ?? "0x0000000000000000000000000000000000000000"],
      },
      {
        ...contracts.vault,
        functionName: "balanceOf",
        args: [address ?? "0x0000000000000000000000000000000000000000"],
      },
      {
        ...contracts.priceFeed,
        functionName: "getPrice",
        args: [activeMarket.id],
      },
    ],
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  const allowance = (reads?.[0]?.result as bigint | undefined) ?? 0n;
  const walletBalance = (reads?.[1]?.result as bigint | undefined) ?? 0n;
  const vaultBalance = (reads?.[2]?.result as bigint | undefined) ?? 0n;
  const currentPrice = (reads?.[3]?.result as bigint | undefined) ?? 0n;

  const { data: longPos } = useReadContract({
    ...contracts.marginManager,
    functionName: "getPosition",
    args: [
      address ?? "0x0000000000000000000000000000000000000000",
      activeMarket.id,
      SIDE.LONG,
    ],
    query: { enabled: !!address && tab === "close" },
  });

  const { data: shortPos } = useReadContract({
    ...contracts.marginManager,
    functionName: "getPosition",
    args: [
      address ?? "0x0000000000000000000000000000000000000000",
      activeMarket.id,
      SIDE.SHORT,
    ],
    query: { enabled: !!address && tab === "close" },
  });

  const { writeContract, data: writeData, isPending: isWritePending, error: writeError } =
    useWriteContract();
  const {
    isLoading: isConfirming,
    isSuccess,
    isError: isReceiptError,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (writeData) setTxHash(writeData);
  }, [writeData]);

  useEffect(() => {
    if (writeError) {
      show("error", "Transaction failed", decodeRevertReason(writeError));
      setPendingStep(null);
    }
  }, [writeError, show]);

  useEffect(() => {
    if (isReceiptError) {
      show("error", "Transaction reverted", decodeRevertReason(receiptError));
      setPendingStep(null);
      setTxHash(undefined);
    }
  }, [isReceiptError, receiptError, show]);

  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      refetchReads();

      if (pendingStep === "approve") {
        show("success", "Approved", "nUSD spending approved for the Vault.");
        setPendingStep("deposit");
        writeContract({
          ...contracts.vault,
          functionName: "deposit",
          args: [depositAmount],
        });
      } else if (pendingStep === "deposit") {
        show("success", "Deposited", `$${formatAmount(depositAmount)} moved into your Vault balance.`);
        setPendingStep("open");
        writeContract({
          ...contracts.positionRouter,
          functionName: "increasePosition",
          args: [activeMarket.id, side, size, collateral],
        });
      } else if (pendingStep === "open") {
        show(
          "success",
          `${side === SIDE.LONG ? "Long" : "Short"} opened`,
          `$${formatAmount(size)} ${activeMarket.symbol} position at ${leverage}x leverage.`
        );
        setPendingStep(null);
        setCollateralInput("");
        setLeverage(1);
        onTraded?.();
      } else if (pendingStep === "close") {
        show("success", "Position closed", "Collateral and PnL moved back to your Vault balance.");
        setPendingStep("withdraw");
        writeContract({
          ...contracts.vault,
          functionName: "withdraw",
          args: [vaultBalance],
        });
      } else if (pendingStep === "withdraw") {
        show("success", "Withdrawn", "Funds sent back to your wallet.");
        setPendingStep(null);
        onTraded?.();
      } else {
        setPendingStep(null);
        onTraded?.();
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess]);

  const needsApproval = !allowance || allowance < depositAmount;
  const hasPosition =
    side === SIDE.LONG
      ? ((longPos as { size: bigint } | undefined)?.size ?? 0n) > 0n
      : ((shortPos as { size: bigint } | undefined)?.size ?? 0n) > 0n;

  const liqPricePreview =
    size > 0n && collateral > 0n && currentPrice > 0n
      ? estimateLiqPrice(size, collateral, currentPrice, MAINTENANCE_BPS, side === SIDE.LONG)
      : null;

  const handleOpen = useCallback(() => {
    if (!address || size === 0n || collateral === 0n) return;

    if (needsApproval) {
      setPendingStep("approve");
      writeContract({
        ...contracts.collateralToken,
        functionName: "approve",
        args: [contracts.vault.address, MAX_UINT256],
      });
    } else if (vaultBalance < depositAmount) {
      setPendingStep("deposit");
      writeContract({
        ...contracts.vault,
        functionName: "deposit",
        args: [depositAmount],
      });
    } else {
      setPendingStep("open");
      writeContract({
        ...contracts.positionRouter,
        functionName: "increasePosition",
        args: [activeMarket.id, side, size, collateral],
      });
    }
  }, [address, size, collateral, depositAmount, side, needsApproval, vaultBalance, writeContract, activeMarket.id]);

  const handleClose = useCallback(() => {
    if (!address) return;
    setPendingStep("close");
    writeContract({
      ...contracts.positionRouter,
      functionName: "closePosition",
      args: [activeMarket.id, side],
    });
  }, [address, side, writeContract, activeMarket.id]);

  const isLoading = isWritePending || isConfirming || pendingStep !== null;

  const walletBalanceFl = (Number(walletBalance) / 1e18).toFixed(2);
  const vaultBalanceFl = (Number(vaultBalance) / 1e18).toFixed(2);

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

  const leverageColor =
    leverage <= 5 ? "var(--accent-long)" : leverage <= 20 ? "var(--accent-warn)" : "var(--accent-short)";

  return (
    <div
      className="border"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
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
        <div className="text-xs px-1" style={{ color: "var(--text-muted)" }}>
          Trading <span style={{ color: "var(--text-primary)", fontWeight: 600 }}>{activeMarket.symbol}</span>
        </div>

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

            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-xs" style={{ color: "var(--text-muted)" }}>
                  Leverage
                </label>
                <span
                  className="font-mono text-sm font-semibold tabular-nums"
                  style={{ color: leverageColor }}
                >
                  {leverage.toFixed(1)}x
                </span>
              </div>
              <input
                type="range"
                min={1}
                max={MAX_LEVERAGE}
                step={0.5}
                value={leverage}
                onChange={(e) => setLeverage(Number(e.target.value))}
                className="w-full"
                style={{ accentColor: leverageColor }}
              />
              <div className="flex justify-between text-[10px] mt-1" style={{ color: "var(--text-muted)" }}>
                <span>1x</span>
                <span>25x</span>
                <span>{MAX_LEVERAGE}x</span>
              </div>
            </div>

            {collateral > 0n && (
              <div className="flex justify-between text-xs px-1" style={{ color: "var(--text-muted)" }}>
                <span>Position size</span>
                <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
                  ${formatAmount(size)}
                </span>
              </div>
            )}

            {liqPricePreview !== null && liqPricePreview > 0 && (
              <div className="flex justify-between text-xs px-1" style={{ color: "var(--text-muted)" }}>
                <span>Est. liquidation price</span>
                <span className="font-mono tabular-nums" style={{ color: "var(--accent-warn)" }}>
                  ${liqPricePreview.toFixed(2)}
                </span>
              </div>
            )}

            {address && vaultBalance > 0n && (
              <div className="text-xs flex justify-between px-1" style={{ color: "var(--text-muted)" }}>
                <span>Trading collateral ready (separate from LP)</span>
                <span className="font-mono tabular-nums" style={{ color: "var(--accent-info)" }}>
                  ${vaultBalanceFl} ready
                </span>
              </div>
            )}

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
          <div className="space-y-3">
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              Closes your {side === SIDE.LONG ? "long" : "short"} {activeMarket.symbol} position and
              withdraws your collateral back to your wallet automatically.
            </p>
            {!address ? (
              <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
                Connect wallet to trade
              </p>
            ) : !hasPosition ? (
              <p className="text-xs text-center py-3" style={{ color: "var(--text-muted)" }}>
                No open {side === SIDE.LONG ? "long" : "short"} {activeMarket.symbol} position
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