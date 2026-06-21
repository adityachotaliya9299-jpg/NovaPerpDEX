"use client";

import { useState, useEffect } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/lib/contracts";
import { useMarket } from "@/lib/market-context";
import { getMarketById } from "@/lib/markets";
import { parseWad, formatAmount, SIDE, type Side } from "@/lib/utils/format";
import { useToast, decodeRevertReason } from "@/components/Toast";
import { fetchActiveOrders, type SubgraphOrder } from "@/lib/subgraph";

function PlaceOrderForm({ onPlaced }: { onPlaced?: () => void }) {
  const { address } = useAccount();
  const { activeMarket } = useMarket();
  const { show } = useToast();
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [sizeInput, setSizeInput] = useState("");
  const [collateralInput, setCollateralInput] = useState("");
  const [triggerInput, setTriggerInput] = useState("");
  const [triggerAbove, setTriggerAbove] = useState(false);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  const size = parseWad(sizeInput);
  const collateral = parseWad(collateralInput);
  const trigger = parseWad(triggerInput);

  useEffect(() => { if (writeData) setTxHash(writeData); }, [writeData]);
  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      show("success", "Order placed", `${side === SIDE.LONG ? "Long" : "Short"} ${activeMarket.symbol} order will execute at ${triggerAbove ? "≥" : "≤"} $${triggerInput}.`);
      setSizeInput(""); setCollateralInput(""); setTriggerInput("");
      // Subgraph indexing lags the chain by a few seconds — give it a moment
      // before refetching, otherwise the new order won't show up yet.
      setTimeout(() => onPlaced?.(), 3000);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess, onPlaced]);
  useEffect(() => {
    if (writeError) show("error", "Order failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Order reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);

  function handlePlace() {
    if (!address || size === 0n || collateral === 0n || trigger === 0n) return;
    writeContract({
      ...contracts.orderBook,
      functionName: "placeOrder",
      args: [activeMarket.id, side, size, collateral, trigger, triggerAbove],
    });
  }

  const isLoading = isPending || isConfirming;

  return (
    <div className="border p-4 space-y-4" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <h3 className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
        Place Limit Order — {activeMarket.symbol}
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

function OrderRow({ order, isExecutable, isOwnOrder, onChanged }: {
  order: SubgraphOrder; isExecutable: boolean;
  isOwnOrder: boolean; onChanged?: () => void;
}) {
  const { show } = useToast();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const { writeContract, data: writeData, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => { if (writeData) setTxHash(writeData); }, [writeData]);
  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      show("success", "Order updated", "");
      setTimeout(() => onChanged?.(), 3000);
    }
  }, [isSuccess, onChanged, show]);
  useEffect(() => {
    if (writeError) show("error", "Action failed", decodeRevertReason(writeError));
  }, [writeError, show]);
  useEffect(() => {
    if (isReceiptError) show("error", "Action reverted", decodeRevertReason(receiptError));
  }, [isReceiptError, receiptError, show]);

  const isLoading = isPending || isConfirming;
  const marketInfo = getMarketById(order.market);
  const orderIdBigInt = BigInt(order.id);

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between gap-3" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span className="text-[10px] px-1 py-0.5" style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}>
          {marketInfo.symbol}
        </span>
        <span className="font-mono tabular-nums" style={{ color: "var(--text-muted)" }}>
          #{order.id}
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
          <button onClick={() => writeContract({ ...contracts.orderBook, functionName: "executeOrder", args: [orderIdBigInt] })}
            disabled={isLoading} className="text-[11px] font-semibold px-2 py-1 transition-opacity disabled:opacity-50"
            style={{ background: "var(--accent-warn)", color: "var(--bg-base)" }}>
            Execute
          </button>
        )}
        {isOwnOrder && (
          <button onClick={() => writeContract({ ...contracts.orderBook, functionName: "cancelOrder", args: [orderIdBigInt] })}
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
  const [orders, setOrders] = useState<SubgraphOrder[]>([]);
  const [executableMap, setExecutableMap] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const active = await fetchActiveOrders();
      setOrders(active);

      // isExecutable still needs a live on-chain read per order — the
      // subgraph knows an order EXISTS and is PLACED, but "has price
      // crossed the trigger yet" is live state the indexer doesn't track.
      // This is a much smaller set of reads than the old full-scan
      // approach (only active orders, not every order ever placed).
      const { contracts: contractsLib } = await import("@/lib/contracts");
      const { createPublicClient, http } = await import("viem");
      const { sepolia } = await import("viem/chains");
      const client = createPublicClient({ chain: sepolia, transport: http() });

      const results = await Promise.allSettled(
        active.map((o) =>
          client.readContract({
            ...contractsLib.orderBook,
            functionName: "isExecutable",
            args: [BigInt(o.id)],
          })
        )
      );
      const map: Record<string, boolean> = {};
      results.forEach((r, i) => {
        map[active[i].id] = r.status === "fulfilled" ? (r.value as boolean) : false;
      });
      setExecutableMap(map);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
      console.error("OrderList (subgraph) load error", e);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    const interval = setInterval(load, 15_000);
    return () => clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshKey]);

  if (loading && orders.length === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Loading orders…</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-xs" style={{ color: "var(--accent-short)" }}>Failed to load orders: {error}</p>
      </div>
    );
  }

  if (orders.length === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>No active orders</p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Place a limit order using the panel on the left.</p>
      </div>
    );
  }

  return (
    <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="px-4 py-2.5 border-b" style={{ borderColor: "var(--border)" }}>
        <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Open Orders — All Markets {loading && <span style={{ color: "var(--text-muted)" }}>…</span>}
        </span>
      </div>
      {orders.map((order) => (
        <OrderRow
          key={order.id}
          order={order}
          isExecutable={executableMap[order.id] ?? false}
          isOwnOrder={!!address && order.account.toLowerCase() === address.toLowerCase()}
          onChanged={load}
        />
      ))}
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
          Order history is indexed via subgraph — instant load regardless of
          how many orders have ever been placed. Anyone can execute an order
          once it&apos;s marked READY, a permissionless keeper pattern not
          limited to the order&apos;s owner.
        </p>
      </div>
    </div>
  );
}