"use client";

import { useState, useMemo, useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { parseWad, formatAmount, formatPrice, SIDE, type Side } from "@/lib/utils/format";

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

/**
 * OrderBook has no per-account enumeration (no `ordersByAccount`-style
 * getter) — only `orders(uint256 id)` for a single order and `nextOrderId()`
 * for the upper bound. To list "my orders" the only option is to read every
 * order id from 0 to nextOrderId-1 and filter client-side. That's fine at
 * testnet scale (dozens of orders) but would not scale to a busy mainnet
 * order book without an indexer — flagged here rather than hidden.
 */
const MAX_ORDERS_TO_SCAN = 200;

function PlaceOrderForm({ onPlaced }: { onPlaced?: () => void }) {
  const { address } = useAccount();
  const [side, setSide] = useState<Side>(SIDE.LONG);
  const [sizeInput, setSizeInput] = useState("");
  const [collateralInput, setCollateralInput] = useState("");
  const [triggerInput, setTriggerInput] = useState("");
  const [triggerAbove, setTriggerAbove] = useState(false);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { writeContract, data: writeData, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const size = parseWad(sizeInput);
  const collateral = parseWad(collateralInput);
  const trigger = parseWad(triggerInput);

  if (writeData && writeData !== txHash) setTxHash(writeData);
  if (isSuccess && txHash) {
    setTxHash(undefined);
    setSizeInput("");
    setCollateralInput("");
    setTriggerInput("");
    onPlaced?.();
  }

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
    <div
      className="border p-4 space-y-4"
      style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
    >
      <h3 className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
        Place Limit Order
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
          Long
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
          Short
        </button>
      </div>

      <div>
        <label className="text-xs mb-1.5 block" style={{ color: "var(--text-muted)" }}>
          Position size (nUSD)
        </label>
        <input
          type="number"
          min="0"
          placeholder="0.00"
          value={sizeInput}
          onChange={(e) => setSizeInput(e.target.value)}
          className="w-full bg-transparent border px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
          style={{ borderColor: "var(--border)", background: "var(--bg-elevated)", color: "var(--text-primary)" }}
        />
      </div>

      <div>
        <label className="text-xs mb-1.5 block" style={{ color: "var(--text-muted)" }}>
          Collateral (nUSD)
        </label>
        <input
          type="number"
          min="0"
          placeholder="0.00"
          value={collateralInput}
          onChange={(e) => setCollateralInput(e.target.value)}
          className="w-full bg-transparent border px-3 py-2.5 text-sm font-mono tabular-nums outline-none"
          style={{ borderColor: "var(--border)", background: "var(--bg-elevated)", color: "var(--text-primary)" }}
        />
      </div>

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
              ? { background: "var(--accent-info)", color: "var(--bg-base)" }
              : { background: "var(--bg-elevated)", color: "var(--text-muted)", border: "1px solid var(--border)" }
          }
        >
          Execute at or below
        </button>
        <button
          onClick={() => setTriggerAbove(true)}
          className="flex-1 py-2 text-xs font-medium transition-opacity"
          style={
            triggerAbove
              ? { background: "var(--accent-info)", color: "var(--bg-base)" }
              : { background: "var(--bg-elevated)", color: "var(--text-muted)", border: "1px solid var(--border)" }
          }
        >
          Execute at or above
        </button>
      </div>

      {!address ? (
        <p className="text-xs text-center py-2" style={{ color: "var(--text-muted)" }}>
          Connect wallet to place orders
        </p>
      ) : (
        <button
          onClick={handlePlace}
          disabled={isLoading || size === 0n || collateral === 0n || trigger === 0n}
          className="w-full py-3 text-sm font-semibold transition-opacity disabled:opacity-40"
          style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
        >
          {isLoading ? (isConfirming ? "Confirming…" : "Sending…") : "Place Order"}
        </button>
      )}

      <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
        Note: placing an order does not lock collateral up front. The order
        only pulls collateral from your wallet when it executes — make sure
        you have nUSD approved and available at execution time.
      </p>
    </div>
  );
}

function OrderRow({
  orderId,
  order,
  isExecutable,
  isOwnOrder,
  onChanged,
}: {
  orderId: number;
  order: RawOrder;
  isExecutable: boolean;
  isOwnOrder: boolean;
  onChanged?: () => void;
}) {
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const { writeContract, data: writeData, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  if (writeData && writeData !== txHash) setTxHash(writeData);
  if (isSuccess && txHash) {
    setTxHash(undefined);
    onChanged?.();
  }

  const isLoading = isPending || isConfirming;
  const isLong = order.side === SIDE.LONG;

  function handleCancel() {
    writeContract({ ...contracts.orderBook, functionName: "cancelOrder", args: [BigInt(orderId)] });
  }
  function handleExecute() {
    writeContract({ ...contracts.orderBook, functionName: "executeOrder", args: [BigInt(orderId)] });
  }

  return (
    <div className="p-3 border-b last:border-b-0 flex items-center justify-between gap-3" style={{ borderColor: "var(--border)" }}>
      <div className="flex items-center gap-3 text-xs">
        <span
          className="font-semibold px-1.5 py-0.5"
          style={{
            background: isLong ? "var(--accent-long)22" : "var(--accent-short)22",
            color: isLong ? "var(--accent-long)" : "var(--accent-short)",
          }}
        >
          {isLong ? "LONG" : "SHORT"}
        </span>
        <span className="font-mono tabular-nums" style={{ color: "var(--text-primary)" }}>
          ${formatAmount(order.sizeDelta)}
        </span>
        <span style={{ color: "var(--text-muted)" }}>
          {order.triggerAbove ? "≥" : "≤"} {formatPrice(order.triggerPrice)}
        </span>
        {isExecutable && (
          <span className="text-[10px] font-medium" style={{ color: "var(--accent-warn)" }}>
            READY
          </span>
        )}
        {!isOwnOrder && (
          <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
            {order.account.slice(0, 6)}…{order.account.slice(-4)}
          </span>
        )}
      </div>
      <div className="flex items-center gap-2">
        {isExecutable && (
          <button
            onClick={handleExecute}
            disabled={isLoading}
            className="text-[11px] font-semibold px-2 py-1 transition-opacity disabled:opacity-50"
            style={{ background: "var(--accent-warn)", color: "var(--bg-base)" }}
          >
            Execute
          </button>
        )}
        {isOwnOrder && (
          <button
            onClick={handleCancel}
            disabled={isLoading}
            className="text-[11px] px-2 py-1 transition-opacity disabled:opacity-50"
            style={{ color: "var(--text-muted)", border: "1px solid var(--border)" }}
          >
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}

function OrderList({ refreshKey }: { refreshKey: number }) {
  const { address } = useAccount();

  const { data: nextIdData, refetch: refetchNextId } = useReadContract({
    ...contracts.orderBook,
    functionName: "nextOrderId",
    query: { refetchInterval: 15_000 },
  });

  useEffect(() => {
    if (refreshKey) refetchNextId();
  }, [refreshKey, refetchNextId]);

  const nextId = Number(nextIdData ?? 0n);
  const scanCount = Math.min(nextId, MAX_ORDERS_TO_SCAN);
  const startId = nextId - scanCount;

  const orderContracts = useMemo(
    () =>
      Array.from({ length: scanCount }, (_, i) => ({
        ...contracts.orderBook,
        functionName: "orders" as const,
        args: [BigInt(startId + i)] as const,
      })),
    [scanCount, startId]
  );

  const { data: ordersData } = useReadContracts({
    contracts: orderContracts,
    query: { enabled: scanCount > 0 },
  });

  const executableContracts = useMemo(
    () =>
      Array.from({ length: scanCount }, (_, i) => ({
        ...contracts.orderBook,
        functionName: "isExecutable" as const,
        args: [BigInt(startId + i)] as const,
      })),
    [scanCount, startId]
  );

  const { data: executableData } = useReadContracts({
    contracts: executableContracts,
    query: { enabled: scanCount > 0, refetchInterval: 15_000 },
  });

  const rows = (ordersData ?? [])
    .map((res, i) => {
      const order = res?.result as RawOrder | undefined;
      if (!order || !order.active) return null;
      const isExecutable = (executableData?.[i]?.result as boolean | undefined) ?? false;
      return { orderId: startId + i, order, isExecutable };
    })
    .filter((r): r is { orderId: number; order: RawOrder; isExecutable: boolean } => r !== null)
    .reverse();

  if (nextId === 0) {
    return (
      <div className="border p-8 text-center" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
        <p className="text-sm font-medium mb-1" style={{ color: "var(--text-primary)" }}>
          No orders yet
        </p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>
          Place a limit order using the panel on the left.
        </p>
      </div>
    );
  }

  return (
    <div className="border overflow-hidden" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      <div className="px-4 py-2.5 border-b flex items-center justify-between" style={{ borderColor: "var(--border)" }}>
        <span className="text-xs font-medium uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          Open Orders
        </span>
        {nextId > MAX_ORDERS_TO_SCAN && (
          <span className="text-[10px]" style={{ color: "var(--accent-warn)" }}>
            Showing most recent {MAX_ORDERS_TO_SCAN} of {nextId}
          </span>
        )}
      </div>
      {rows.length === 0 ? (
        <p className="text-xs text-center py-6" style={{ color: "var(--text-muted)" }}>
          No active orders right now.
        </p>
      ) : (
        rows.map(({ orderId, order, isExecutable }) => (
          <OrderRow
            key={orderId}
            orderId={orderId}
            order={order}
            isExecutable={isExecutable}
            isOwnOrder={!!address && order.account.toLowerCase() === address.toLowerCase()}
          />
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