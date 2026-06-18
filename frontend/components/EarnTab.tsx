"use client";

import { useState } from "react";
import { LPVaultPanel } from "@/components/LPVaultPanel";
import { StakingPanel } from "@/components/StakingPanel";

export function EarnTab() {
  const [, setRefreshKey] = useState(0);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 items-start">
      <LPVaultPanel onChanged={() => setRefreshKey((k) => k + 1)} />
      <StakingPanel onChanged={() => setRefreshKey((k) => k + 1)} />
    </div>
  );
}