"use client";

export function RefreshPrice() {
  return (
    <div
      className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] font-medium"
      style={{ color: "var(--accent-long)" }}
      title="Price feeds live from Chainlink on Sepolia — no manual updates needed"
    >
      <span
        className="inline-block w-1.5 h-1.5 rounded-full"
        style={{ background: "var(--accent-long)" }}
      />
      Live · Chainlink
    </div>
  );
}