"use client";

import { Header } from "@/components/Header";
import { RewardsHub } from "@/components/RewardsHub";

export default function RewardsPage() {
  return (
    <div className="min-h-screen flex flex-col" style={{ background: "var(--bg-base)" }}>
      <Header />
      <main className="flex-1 max-w-screen-xl mx-auto w-full px-4 py-6">
        <h1 className="text-lg font-semibold mb-6" style={{ color: "var(--text-primary)" }}>
          Rewards Hub
        </h1>
        <RewardsHub />
      </main>
    </div>
  );
}