"use client";

import { useState, useEffect } from "react";
import { useAccount, usePublicClient, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { sepolia } from "viem/chains";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { parseWad, formatAmount, formatPrice, SIDE, type Side } from "@/lib/utils/format";
import { useToast, decodeRevertReason } from "@/components/Toast";

interface RawOrder {
  account: `0x${string}`;
  market: `0x${string}`;
  side: number;
  sizeDelta: bigint;
  collateralDelta: bigint;
  triggerPrice: bigint;
  triggerAbove: boolean;
  active: boolean;
}

const MAX_ORDERS_TO_SCAN = 200;

function PlaceOrderForm({ onPlaced }: { onPlaced?: () => void }) {
  const { address } = useAccount();
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [sizeInput, setSizeInput] = useState("");
  const [collateralInput, setCollateralInput] = useState("");
  const [triggerInput, setTriggerInput] = useState("");
  const [triggerAbove, setTriggerAbove] = useState(false);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { show } = useToast();
  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (writeError) show("error", "Order failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Order reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);

  const size = parseWad(sizeInput);
  const collateral = parseWad(collateralInput);
  const trigger = parseWad(triggerInput);

  useEffect(() => { if (writeData) setTxHash(writeData); }, [writeData]);
  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      show("success", "Order placed", `${side === SIDE.LONG ? "Long" : "Short"} order will execute at ${triggerAbove ? "≥" : "≤"} $${triggerInput}.`);
      setSizeInput(""); setCollateralInput(""); setTriggerInput("");
      onPlaced?.();
    }
  }, [isSuccess, onPlaced]);

  function handlePlace() {
    if (!address || size === 0n || collateral === 0n || trigger === 0n) return;
    writeContract({
      ...contracts.orderBook,
      functionName: "placeOrder",
      args: [ETH_USD_MARKET, side, size, collateral, trigger, triggerAbove],
    });
  }

  const isLoading = isPending || isConfirming;

  return (
    <div className="border p-4 space-y-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <h3 className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
        Place Limit Order
      </h3>

      <div className="flex gap-2">
        {([SIDE.LONG, SIDE.SHORT] as const).map((s) => (
          <button key={s} onClick={() => setSide(s)} className="flex-1 py-2 text-sm font-semibold transition-opacity"
            style={side === s
              ? { background: s === SIDE.LONG ? "var(--accent-long)" : "var(--accent-short)", color: s === SIDE.LONG ? "var(--bg-base)" : "#fff" }
              : { background: "var(--bg-elevated)", color: "var(--text-primary)", border: "1px solid var(--border)", opacity: 0.55 }}>
            {s === SIDE.LONG ? "Long" : "Short"}
          </button>
        ))}
      </div>

      {[
        { label: "Position size (nUSD)", value: sizeInput, set: setSizeInput },
        { label: "Collateral (nUSD)", value: collateralInput, set: setCollateralInput },
        { label: "Trigger price (USD)", value: triggerInput, set: setTriggerInput },
      ].map(({ label, value, set }) => (
        <div key={label}>
          <label className="text-xs mb-1.5 block" style={{ color: "var(--text-muted)" }}>{label}</label>
          <input type="number" min="0" placeholder="0.00" value={value}
            onChange={(e) => set(e.target.value)}
            className="w-full bg-transparent border px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
            style={{ borderColor: "var(--border)", background: "var(--bg-elevated)", color: "var(--text-primary)" }} />
        </div>
      ))}

      <div className="flex gap-2">
        {[false, true].map((above) => (
          <button key={String(above)} onClick={() => setTriggerAbove(above)}
            className="flex-1 py-2 text-xs font-medium transition-opacity"
            style={triggerAbove === above
              ? { background: "var(--accent-info)", color: "var(--bg-base)" }
              : { background: "var(--bg-elevated)", color: "var(--text-muted)", border: "1px solid var(--border)" }}>
            {above ? "Execute at or above" : "Execute at or below"}
          </button>
        ))}
      </div>

      {!address ? (
        <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>Connect wallet to place orders</p>
      ) : (
        <button onClick={handlePlace} disabled={isLoading || size === 0n || collateral === 0n || trigger === 0n}
          className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
          style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}>
          {isLoading ? (isConfirming ? "Confirming…" : "Sending…") : "Place Order"}
        </button>
      )}

      <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
        Note: placing an order does not lock collateral up front. The order only pulls
        collateral from your wallet when it executes — make sure you have nUSD approved
        and available at execution time.
      </p>
    </div>
  );
}

function OrderRow({ orderId, order, isExecutable, isOwnOrder, onChanged }: {
  orderId: number; order: RawOrder; isExecutable: boolean;
  isOwnOrder: boolean; onChanged?: () => void;
}) {
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const { show } = useToast();
  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => { if (writeData) setTxHash(writeData); }, [writeData]);
  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      show("success", "Order updated", "");
      onChanged?.();
    }
  }, [isSuccess, onChanged, show]);
  useEffect(() => {
    if (writeError) show("error", "Action failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Action reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);
  const isLoading = isPending || isConfirming;
  const isLong = order.side === SIDE.LONG;

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between gap-3" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span className="font-semibold px-1.5 py-0.5"
          style={{ background: isLong ? "var(--accent-long)22" : "var(--accent-short)22", color: isLong ? "var(--accent-long)" : "var(--accent-short)" }}>
          {isLong ? "LONG" : "SHORT"}
        </span>
        <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${formatAmount(order.sizeDelta)}
        </span>
        <span style={{ color: "var(--text-muted)" }}>
          {order.triggerAbove ? "≥" : "≤"} {formatPrice(order.triggerPrice)}
        </span>
        {isExecutable && (
          <span className="text-[10px] font-medium" style={{ color: "var(--accent-warn)" }}>READY</span>
        )}
        {!isOwnOrder && (
          <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
            {order.account.slice(0, 6)}…{order.account.slice(-4)}
          </span>
        )}
      </div>
      <div className="flex items-center gap-2">
        {isExecutable && (
          <button onClick={() => writeContract({ ...contracts.orderBook, functionName: "executeOrder", args: [BigInt(orderId)] })}
            disabled={isLoading} className="text-[11px] font-semibold px-2 py-1 transition-opacity disabled:opacity-50"
            style={{ background: "var(--accent-warn)", color: "var(--bg-base)" }}>
            Execute
          </button>
        )}
        {isOwnOrder && (
          <button onClick={() => writeContract({ ...contracts.orderBook, functionName: "cancelOrder", args: [BigInt(orderId)] })}
            disabled={isLoading} className="text-[11px] px-2 py-1 transition-opacity disabled:opacity-50"
            style={{ color: "var(--text-muted)", border: "1px solid var(--border)" }}>
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}

function OrderList({ refreshKey }: { refreshKey: number }) {
  const { address } = useAccount();
  // Explicitly target Sepolia so this works regardless of which chain MetaMask reports
  const client = usePublicClient({ chainId: sepolia.id });
  const [nextId, setNextId] = useState<number | null>(null);
  const [rows, setRows] = useState<{ orderId: number; order: RawOrder; isExecutable: boolean }[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    if (!client) {
      setError("No RPC client available");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const nid = await client.readContract({
        ...contracts.orderBook,
        functionName: "nextOrderId",
        args: [],
      }) as bigint;
      const n = Number(nid);
      setNextId(n);
      if (n === 0) { setRows([]); return; }

      const scanCount = Math.min(n, MAX_ORDERS_TO_SCAN);
      const startId = n - scanCount;

      const fetches = await Promise.allSettled(
        Array.from({ length: scanCount }, async (_, i) => {
          const orderId = startId + i;
          const [rawOrder, isExec] = await Promise.all([
            client.readContract({
              ...contracts.orderBook,
              functionName: "orders",
              args: [BigInt(orderId)],
            }),
            client.readContract({
              ...contracts.orderBook,
              functionName: "isExecutable",
              args: [BigInt(orderId)],
            }).catch(() => false),
          ]);
          return { orderId, rawOrder, isExec: isExec as boolean };
        })
      );

      const result: typeof rows = [];
      for (const f of fetches) {
        if (f.status !== "fulfilled") continue;
        const { orderId, rawOrder, isExec } = f.value;
         const t = rawOrder as unknown as readonly unknown[];
        const active = Boolean(t[7]);
        if (!active) continue;
        const order: RawOrder = {
          account: t[0] as `0x${string}`,
          market: t[1] as `0x${string}`,
          side: Number(t[2]),
          sizeDelta: t[3] as bigint,
          collateralDelta: t[4] as bigint,
          triggerPrice: t[5] as bigint,
          triggerAbove: Boolean(t[6]),
          active: true,
        };
        result.push({ orderId, order, isExecutable: isExec });
      }
      setRows(result.reverse());
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
      console.error("OrderList load error", e);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!client) return;
    load();
    const interval = setInterval(load, 15_000);
    return () => clearInterval(interval);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshKey, client]);

  if (nextId === null) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        {error ? (
          <p className="text-xs" style={{ color: "var(--accent-short)" }}>
            Failed to load orders: {error}
          </p>
        ) : (
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>Loading orders…</p>
        )}
      </div>
    );
  }

  if (nextId === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>No orders yet</p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Place a limit order using the panel on the left.</p>
      </div>
    );
  }

  return (
    <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="px-4 py-2.5 border-b flex items-center justify-between" style={{ borderColor: "var(--border)" }}>
        <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Open Orders {loading && <span style={{ color: "var(--text-muted)" }}>…</span>}
        </span>
        {nextId > MAX_ORDERS_TO_SCAN && (
          <span className="text-[10px]" style={{ color: "var(--accent-warn)" }}>
            Showing most recent {MAX_ORDERS_TO_SCAN} of {nextId}
          </span>
        )}
      </div>
      {error && (
        <p className="text-xs text-center py-3" style={{ color: "var(--accent-short)" }}>
          {error}
        </p>
      )}
      {rows.length === 0 && !error ? (
        <p className="text-xs text-center py-6" style={{ color: "var(--text-muted)" }}>
          No active orders right now.
        </p>
      ) : (
        rows.map(({ orderId, order, isExecutable }) => (
          <OrderRow key={orderId} orderId={orderId} order={order} isExecutable={isExecutable}
            isOwnOrder={!!address && order.account.toLowerCase() === address.toLowerCase()}
            onChanged={load} />
        ))
      )}
    </div>
  );
}

export function OrdersTab() {
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-[340px_1fr] gap-4 items-start">
      <PlaceOrderForm onPlaced={() => setRefreshKey((k) => k + 1)} />
      <div className="space-y-4">
        <OrderList refreshKey={refreshKey} />
        <p className="text-[11px] px-1" style={{ color: "var(--text-muted)" }}>
          Anyone can execute an order once it&apos;s marked READY — this is a
          permissionless keeper pattern, not limited to the order&apos;s owner.
          Orders from all accounts are shown here since the contract has no
          per-account index to filter by.
        </p>
      </div>
    </div>
  );
}