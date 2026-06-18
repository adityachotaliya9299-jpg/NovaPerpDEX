"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";
import { formatPrice, parseWad } from "@/lib/utils/format";

/**
 * PriceFeed enforces a staleness window (1 hour, set in Deploy.s.sol's
 * STALENESS constant). Since there's no live keeper bot pushing prices on
 * an interval yet, every read of getPrice() will start reverting once more
 * than an hour has passed since the last setPrice call — which is exactly
 * what causes the price ticker to show "—" instead of a number.
 *
 * This control lets whoever holds PRICE_KEEPER_ROLE (the deployer, by
 * default — see RoleManager.grantRole(PRICE_KEEPER_ROLE, admin) in
 * Deploy.s.sol Phase 2) push a fresh price with one click instead of
 * reaching for `cast send` before every demo/testing session.
 *
 * Only rendered at all when the connected wallet is the configured
 * NEXT_PUBLIC_PRICE_KEEPER_ADDRESS — everyone else doesn't see it, since
 * calling setPrice without the role would just revert anyway.
 */
const KEEPER_ADDRESS = (process.env.NEXT_PUBLIC_PRICE_KEEPER_ADDRESS ?? "").toLowerCase();

export function RefreshPrice() {
  const { address } = useAccount();
  const [priceInput, setPriceInput] = useState("2000");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { data: currentPrice, refetch: refetchPrice } = useReadContract({
    ...contracts.priceFeed,
    functionName: "getPrice",
    args: [ETH_USD_MARKET],
    query: { refetchInterval: 10_000 },
  });

  const { writeContract, data: writeData, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (writeData) setTxHash(writeData);
  }, [writeData]);

  useEffect(() => {
    if (isSuccess) {
      setTxHash(undefined);
      refetchPrice();
    }
  }, [isSuccess, refetchPrice]);

  if (!address || address.toLowerCase() !== KEEPER_ADDRESS || !KEEPER_ADDRESS) {
    return null;
  }

  const isStale = !currentPrice;
  const isLoading = isPending || isConfirming;

  function handleRefresh() {
    const wad = parseWad(priceInput);
    if (wad === 0n) return;
    writeContract({
      ...contracts.priceFeed,
      functionName: "setPrice",
      args: [ETH_USD_MARKET, wad],
    });
  }

  return (
    <div
      className="flex items-center gap-2 px-3 py-1.5 border"
      style={{
        borderColor: isStale ? "var(--accent-warn)" : "var(--border)",
        background: "var(--bg-elevated)",
      }}
    >
      {isStale && (
        <span className="text-[10px] font-medium" style={{ color: "var(--accent-warn)" }}>
          STALE
        </span>
      )}
      <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
        {currentPrice ? formatPrice(currentPrice) : "no price"}
      </span>
      <input
        type="number"
        value={priceInput}
        onChange={(e) => setPriceInput(e.target.value)}
        className="w-16 bg-transparent text-xs font-mono tabular-nums outline-none border-b"
        style={{ color: "var(--text-primary)", borderColor: "var(--border)" }}
      />
      <button
        onClick={handleRefresh}
        disabled={isLoading}
        className="text-[10px] font-semibold px-2 py-1 transition-opacity disabled:opacity-50"
        style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
      >
        {isLoading ? (isConfirming ? "Confirming…" : "Sending…") : "Push Price"}
      </button>
    </div>
  );
}