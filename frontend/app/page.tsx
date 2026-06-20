"use client";

import Link from "next/link";
import { useReadContracts } from "wagmi";
import { contracts, ETH_USD_MARKET } from "@/lib/contracts";

function formatUsd(value: bigint | undefined, decimals = 0): string {
  if (value === undefined) return "—";
  const num = Number(value) / 1e18;
  return num.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: decimals,
  });
}

export default function LandingPage() {
  const { data } = useReadContracts({
    contracts: [
      { ...contracts.lpVault, functionName: "totalAssets" },
      { ...contracts.priceFeed, functionName: "getPrice", args: [ETH_USD_MARKET] },
      { ...contracts.marginManager, functionName: "longOpenInterest", args: [ETH_USD_MARKET] },
      { ...contracts.marginManager, functionName: "shortOpenInterest", args: [ETH_USD_MARKET] },
    ],
    query: { refetchInterval: 15_000 },
  });

  const tvl = data?.[0]?.result as bigint | undefined;
  const ethPrice = data?.[1]?.result as bigint | undefined;
  const longOi = data?.[2]?.result as bigint | undefined;
  const shortOi = data?.[3]?.result as bigint | undefined;
  const totalOi =
    longOi !== undefined && shortOi !== undefined ? longOi + shortOi : undefined;

  return (
    <div className="min-h-screen flex flex-col" style={{ background: "var(--bg-base)" }}>
      {/* Header */}
      <header
        className="flex items-center justify-between px-6 py-4 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        <span
          className="text-lg font-bold tracking-tight"
          style={{ color: "var(--accent-info)" }}
        >
          NOVAPERPDEX
        </span>
        <Link
          href="/trade"
          className="px-4 py-2 text-sm font-semibold transition-opacity hover:opacity-90"
          style={{ background: "var(--accent-info)", color: "var(--bg-base)" }}
        >
          Launch App
        </Link>
      </header>

      {/* Hero */}
      <section className="flex-1 flex flex-col items-center justify-center text-center px-6 py-20">
        <p
          className="text-xs font-mono tracking-[0.2em] uppercase mb-6"
          style={{ color: "var(--text-muted)" }}
        >
          Sepolia Testnet · Live Chainlink Pricing
        </p>

        <h1
          className="text-4xl sm:text-6xl font-bold tracking-tight leading-[1.05] mb-6 max-w-3xl"
          style={{ color: "var(--text-primary)" }}
        >
          Trade perpetual futures.
          <br />
          <span style={{ color: "var(--accent-long)" }}>Fully on-chain.</span>
        </h1>

        <p
          className="text-base sm:text-lg max-w-xl mb-10"
          style={{ color: "var(--text-muted)" }}
        >
          Up to 50x leverage on ETH-USD. No order book operator, no custody,
          no IOUs — every position, every liquidation, every dollar of
          collateral lives in audited smart contracts you can read yourself.
        </p>

        <Link
          href="/trade"
          className="px-8 py-3.5 text-base font-semibold transition-opacity hover:opacity-90 mb-14"
          style={{ background: "var(--accent-long)", color: "var(--bg-base)" }}
        >
          Start Trading →
        </Link>

        {/* Live stats strip — the signature element: real numbers, not claims */}
        <div
          className="flex flex-wrap items-center justify-center gap-x-10 gap-y-4 px-8 py-5 border"
          style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
        >
          <StatItem label="TVL" value={formatUsd(tvl, 0)} accent="var(--text-primary)" />
          <Divider />
          <StatItem
            label="ETH-USD"
            value={formatUsd(ethPrice, 2)}
            accent="var(--accent-long)"
            live
          />
          <Divider />
          <StatItem
            label="Open Interest"
            value={formatUsd(totalOi, 0)}
            accent="var(--text-primary)"
          />
          <Divider />
          <StatItem label="Max Leverage" value="50x" accent="var(--accent-info)" />
        </div>
      </section>

      {/* Architecture strip */}
      <section
        className="border-t px-6 py-10"
        style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}
      >
        <div className="max-w-screen-lg mx-auto grid grid-cols-2 sm:grid-cols-4 gap-8 text-center">
          <ArchStat value="26" label="Contracts" />
          <ArchStat value="493" label="Tests passing" />
          <ArchStat value="2" label="Oracle sources" />
          <ArchStat value="0" label="Order book operators" />
        </div>
      </section>

      {/* How it works */}
      <section className="px-6 py-16 max-w-screen-md mx-auto w-full">
        <h2
          className="text-xl font-semibold mb-8 text-center"
          style={{ color: "var(--text-primary)" }}
        >
          How a position actually works
        </h2>
        <div className="space-y-6">
          <Step
            title="Collateral goes into a Vault contract you can verify"
            body="Deposit nUSD, it's tracked as your free balance in Vault — not pooled with an operator's funds, not rehypothecated."
          />
          <Step
            title="Price comes from Chainlink, cross-checked against an on-chain TWAP"
            body="OracleAggregator rejects the mark price if Chainlink and the time-weighted average diverge past a guard band — a single manipulated feed can't move your liquidation price alone."
          />
          <Step
            title="Liquidations are permissionless and public"
            body="Any keeper — including the bot running for this deployment, or you — can call liquidate() on an underwater position. No discretionary close, no operator judgment call."
          />
        </div>
      </section>

      {/* Footer */}
      <footer
        className="border-t px-6 py-6 flex flex-wrap items-center justify-between gap-4 text-xs"
        style={{ borderColor: "var(--border)", color: "var(--text-muted)" }}
      >
        <span>NovaPerpDEX — built by Aditya Chotaliya</span>
        <div className="flex gap-6">
          <a
            href="https://github.com/adityachotaliya9299-jpg"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:opacity-80"
          >
            GitHub
          </a>
          <Link href="/trade" className="hover:opacity-80">
            Launch App
          </Link>
        </div>
      </footer>
    </div>
  );
}

function StatItem({
  label,
  value,
  accent,
  live,
}: {
  label: string;
  value: string;
  accent: string;
  live?: boolean;
}) {
  return (
    <div className="flex flex-col items-center gap-1">
      <span
        className="font-mono tabular-nums text-xl font-semibold flex items-center gap-1.5"
        style={{ color: accent }}
      >
        {live && (
          <span
            className="inline-block w-1.5 h-1.5 rounded-full"
            style={{ background: "var(--accent-long)" }}
          />
        )}
        {value}
      </span>
      <span
        className="text-[11px] uppercase tracking-wide"
        style={{ color: "var(--text-muted)" }}
      >
        {label}
      </span>
    </div>
  );
}

function Divider() {
  return <div className="hidden sm:block w-px h-8" style={{ background: "var(--border)" }} />;
}

function ArchStat({ value, label }: { value: string; label: string }) {
  return (
    <div>
      <div
        className="font-mono text-2xl font-bold mb-1"
        style={{ color: "var(--text-primary)" }}
      >
        {value}
      </div>
      <div className="text-xs" style={{ color: "var(--text-muted)" }}>
        {label}
      </div>
    </div>
  );
}

function Step({ title, body }: { title: string; body: string }) {
  return (
    <div className="border-l-2 pl-5 py-1" style={{ borderColor: "var(--accent-info)" }}>
      <h3 className="text-sm font-semibold mb-1.5" style={{ color: "var(--text-primary)" }}>
        {title}
      </h3>
      <p className="text-sm leading-relaxed" style={{ color: "var(--text-muted)" }}>
        {body}
      </p>
    </div>
  );
}