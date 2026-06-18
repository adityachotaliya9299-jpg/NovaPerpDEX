"use client";

export type Tab = "trade" | "orders" | "stops" | "earn" | "portfolio";

const TABS: { id: Tab; label: string }[] = [
  { id: "trade", label: "Trade" },
  { id: "orders", label: "Orders" },
  { id: "stops", label: "Stop-Loss" },
  { id: "earn", label: "Earn" },
  { id: "portfolio", label: "Portfolio" },
];

export function TabNav({ active, onChange }: { active: Tab; onChange: (t: Tab) => void }) {
  return (
    <nav className="flex gap-1 px-4 border-b" style={{ borderColor: "var(--border)", background: "var(--bg-surface)" }}>
      {TABS.map((t) => (
        <button
          key={t.id}
          onClick={() => onChange(t.id)}
          className="px-4 py-3 text-sm font-medium transition-colors"
          style={{
            color: active === t.id ? "var(--text-primary)" : "var(--text-muted)",
            borderBottom: active === t.id ? "2px solid var(--accent-info)" : "2px solid transparent",
          }}
        >
          {t.label}
        </button>
      ))}
    </nav>
  );
}