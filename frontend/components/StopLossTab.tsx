"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/lib/contracts";
import { useMarket } from "@/lib/market-context";
import { parseWad, SIDE, type Side } from "@/lib/utils/format";
import { useToast, decodeRevertReason } from "@/components/Toast";

export function StopLossTab() {
  const { address } = useAccount();
  const { activeMarket } = useMarket();
  const { show } = useToast();
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [triggerInput, setTriggerInput] = useState("");
  const [triggerAbove, setTriggerAbove] = useState(false);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { data: longPos } = useReadContract({
    ...contracts.marginManager,
    functionName: "getPosition",
    args: [address ?? "0x0000000000000000000000000000000000000000", activeMarket.id, SIDE.LONG],
    query: { enabled: !!address },
  });
  const { data: shortPos } = useReadContract({
    ...contracts.marginManager,
    functionName: "getPosition",
    args: [address ?? "0x0000000000000000000000000000000000000000", activeMarket.id, SIDE.SHORT],
    query: { enabled: !!address },
  });

  const { data: isExecutable, refetch: refetchExecutable } = useReadContract({
    ...contracts.stopLossManager,
    functionName: "isExecutable",
    args: [address ?? "0x0000000000000000000000000000000000000000", activeMarket.id, side],
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (writeData) setTxHash(writeData);
  }, [writeData]);

  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      show("success", "Trigger updated", "");
      setTriggerInput("");
      refetchExecutable();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess, refetchExecutable]);

  useEffect(() => {
    if (writeError) show("error", "Action failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Action reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);

  const hasPosition =
    side === SIDE.LONG
      ? ((longPos as { size: bigint } | undefined)?.size ?? 0n) > 0n
      : ((shortPos as { size: bigint } | undefined)?.size ?? 0n) > 0n;

  const isLoading = isPending || isConfirming;
  const trigger = parseWad(triggerInput);

  function handleSetTrigger() {
    if (!address || trigger === 0n) return;
    writeContract({
      ...contracts.stopLossManager,
      functionName: "setTrigger",
      args: [activeMarket.id, side, trigger, triggerAbove],
    });
  }

  function handleCancel() {
    writeContract({
      ...contracts.stopLossManager,
      functionName: "cancelTrigger",
      args: [activeMarket.id, side],
    });
  }

  function handleExecute() {
    if (!address) return;
    writeContract({
      ...contracts.stopLossManager,
      functionName: "executeTrigger",
      args: [address, activeMarket.id, side],
    });
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-[340px_1fr] gap-4 items-start">
      <div className="border p-4 space-y-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <h3 className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Stop-Loss / Take-Profit — {activeMarket.symbol}
        </h3>

        <div className="flex gap-2">
          <button
            onClick={() => setSide(SIDE.LONG)}
            className="flex-1 py-2 text-sm font-semibold transition-opacity"
            style={
              side === SIDE.LONG
                ? { background: "var(--accent-long)", color: "var(--bg-base)" }
                : { background: "var(--bg-elevated)", color: "var(--text-primary)", border: "1px solid var(--border)", opacity: 0.55 }
            }
          >
            Long position
          </button>
          <button
            onClick={() => setSide(SIDE.SHORT)}
            className="flex-1 py-2 text-sm font-semibold transition-opacity"
            style={
              side === SIDE.SHORT
                ? { background: "var(--accent-short)", color: "#fff" }
                : { background: "var(--bg-elevated)", color: "var(--text-primary)", border: "1px solid var(--border)", opacity: 0.55 }
            }
          >
            Short position
          </button>
        </div>

        {!address ? (
          <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
            Connect wallet to set a trigger
          </p>
        ) : !hasPosition ? (
          <p className="text-xs text-center py-3" style={{ color: "var(--text-muted)" }}>
            You don&apos;t have an open {side === SIDE.LONG ? "long" : "short"} position on {activeMarket.symbol}.
          </p>
        ) : (
          <>
            <div>
              <label className="text-xs mb-1.5 block" style={{ color: "var(--text-muted)" }}>
                Trigger price (USD)
              </label>
              <input
                type="number"
                min="0"
                placeholder="0.00"
                value={triggerInput}
                onChange={(e) => setTriggerInput(e.target.value)}
                className="w-full bg-transparent border px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
                style={{ borderColor: "var(--border)", background: "var(--bg-elevated)", color: "var(--text-primary)" }}
              />
            </div>

            <div className="flex gap-2">
              <button
                onClick={() => setTriggerAbove(false)}
                className="flex-1 py-2 text-xs font-medium transition-opacity"
                style={
                  !triggerAbove
                    ? { background: "var(--accent-short)", color: "#fff" }
                    : { background: "var(--bg-elevated)", color: "var(--text-muted)", border: "1px solid var(--border)" }
                }
              >
                Trigger if price falls to
              </button>
              <button
                onClick={() => setTriggerAbove(true)}
                className="flex-1 py-2 text-xs font-medium transition-opacity"
                style={
                  triggerAbove
                    ? { background: "var(--accent-long)", color: "var(--bg-base)" }
                    : { background: "var(--bg-elevated)", color: "var(--text-muted)", border: "1px solid var(--border)" }
                }
              >
                Trigger if price rises to
              </button>
            </div>

            <button
              onClick={handleSetTrigger}
              disabled={isLoading || trigger === 0n}
              className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
              style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
            >
              {isLoading ? (isConfirming ? "Confirming…" : "Sending…") : "Set Trigger"}
            </button>

            <button
              onClick={handleCancel}
              disabled={isLoading}
              className="w-full py-2 text-xs transition-opacity disabled:opacity-50"
              style={{ color: "var(--text-muted)", border: "1px solid var(--border)" }}
            >
              Cancel my trigger on this side
            </button>
          </>
        )}
      </div>

      <div className="border p-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <h3 className="text-xs font-medium uppercase tracking-wider mb-3" style={{ color: "var(--text-muted)" }}>
          Trigger Status — {activeMarket.symbol} {side === SIDE.LONG ? "Long" : "Short"}
        </h3>
        {!address ? (
          <p className="text-sm" style={{ color: "var(--text-muted)" }}>
            Connect your wallet to check trigger status.
          </p>
        ) : (
          <div className="space-y-3">
            <div className="flex items-center gap-2">
              <span
                className="text-xs font-semibold px-2 py-1"
                style={
                  isExecutable
                    ? { background: "var(--accent-warn)22", color: "var(--accent-warn)" }
                    : { background: "var(--bg-elevated)", color: "var(--text-muted)" }
                }
              >
                {isExecutable ? "READY TO EXECUTE" : "NOT TRIGGERED"}
              </span>
              {isExecutable && (
                <button
                  onClick={handleExecute}
                  disabled={isLoading}
                  className="text-xs font-semibold px-3 py-1.5 transition-opacity disabled:opacity-50"
                  style={{ background: "var(--accent-warn)", color: "var(--bg-base)" }}
                >
                  Execute now
                </button>
              )}
            </div>
            <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
              The contract doesn&apos;t expose a way to read back a trigger&apos;s
              configured price once set — only whether the current price has
              already crossed it. &quot;Not triggered&quot; means either no trigger
              is set, or one is set but hasn&apos;t been crossed yet.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}