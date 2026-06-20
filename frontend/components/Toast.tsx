"use client";

import { createContext, useCallback, useContext, useRef, useState } from "react";

type ToastKind = "success" | "error" | "info";

interface ToastItem {
  id: number;
  kind: ToastKind;
  title: string;
  detail?: string;
}

interface ToastContextValue {
  show: (kind: ToastKind, title: string, detail?: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

/**
 * Decodes common on-chain revert patterns into something a person can
 * actually act on, instead of "execution reverted" or a raw hex selector.
 * Falls back to the raw message if nothing matches — never hides
 * information, just adds a plain-language layer in front of it.
 */
export function decodeRevertReason(err: unknown): string {
  const raw =
    (err as { shortMessage?: string; message?: string })?.shortMessage ??
    (err as { message?: string })?.message ??
    String(err);

  if (/InsufficientFree/i.test(raw)) {
    return "Not enough free balance in the Vault to cover this — deposit more or reduce the amount.";
  }
  if (/user rejected|user denied/i.test(raw)) {
    return "Transaction was rejected in your wallet.";
  }
  if (/NotOrderOwner/i.test(raw)) {
    return "Only the account that placed this order can cancel it.";
  }
  if (/NoPosition/i.test(raw)) {
    return "There's no open position to act on.";
  }
  if (/TriggerNotMet/i.test(raw)) {
    return "Price hasn't crossed the trigger level yet.";
  }
  if (/insufficient funds/i.test(raw)) {
    return "Not enough Sepolia ETH in your wallet to cover gas.";
  }
  // Trim viem's long internal stack dump down to the first line, which is
  // usually the actually useful part.
  const firstLine = raw.split("\n")[0];
  return firstLine.length > 140 ? firstLine.slice(0, 140) + "…" : firstLine;
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const idRef = useRef(0);

  const show = useCallback((kind: ToastKind, title: string, detail?: string) => {
    const id = ++idRef.current;
    setToasts((prev) => [...prev, { id, kind, title, detail }]);
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, kind === "error" ? 7000 : 4500);
  }, []);

  const dismiss = (id: number) => setToasts((prev) => prev.filter((t) => t.id !== id));

  return (
    <ToastContext.Provider value={{ show }}>
      {children}
      <div className="fixed bottom-4 right-4 z-[100] flex flex-col gap-2 w-[340px] max-w-[calc(100vw-2rem)]">
        {toasts.map((t) => (
          <ToastCard key={t.id} toast={t} onDismiss={() => dismiss(t.id)} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastCard({ toast, onDismiss }: { toast: ToastItem; onDismiss: () => void }) {
  const accent =
    toast.kind === "success"
      ? "var(--accent-long)"
      : toast.kind === "error"
      ? "var(--accent-short)"
      : "var(--accent-info)";

  return (
    <div
      className="border px-4 py-3 shadow-lg animate-[toast-in_0.2s_ease-out]"
      style={{
        borderColor: "var(--border)",
        background: "var(--bg-surface)",
        borderLeftColor: accent,
        borderLeftWidth: "3px",
      }}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
          {toast.title}
        </p>
        <button
          onClick={onDismiss}
          className="text-xs leading-none opacity-50 hover:opacity-100"
          style={{ color: "var(--text-muted)" }}
          aria-label="Dismiss"
        >
          ✕
        </button>
      </div>
      {toast.detail && (
        <p className="text-xs mt-1 leading-relaxed" style={{ color: "var(--text-muted)" }}>
          {toast.detail}
        </p>
      )}
    </div>
  );
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used inside <ToastProvider>");
  return ctx;
}