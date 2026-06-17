"use client";

import { type ReactNode, useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { RainbowKitProvider, darkTheme } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import { wagmiConfig } from "@/lib/wagmi";

const rainbowKitTheme = darkTheme({
  accentColor: "#3ddc97",
  accentColorForeground: "#0a0e17",
  borderRadius: "small",
  fontStack: "system",
  overlayBlur: "small",
});

export function Providers({ children }: { children: ReactNode }) {
  // useState ensures one QueryClient per browser session, not per render.
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={rainbowKitTheme}>{children}</RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}