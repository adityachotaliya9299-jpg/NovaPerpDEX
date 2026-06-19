import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { defineChain, http } from "viem";
import { sepolia } from "viem/chains";

export const anvil = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
  testnet: true,
});

const WALLETCONNECT_PROJECT_ID =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "00000000000000000000000000000000";

const SEPOLIA_RPC =
  process.env.NEXT_PUBLIC_RPC_URL || "https://sepolia.drpc.org";

export const wagmiConfig = getDefaultConfig({
  appName: "NovaPerpDEX",
  projectId: WALLETCONNECT_PROJECT_ID,
  chains: [sepolia, anvil],
  transports: {
    [sepolia.id]: http(SEPOLIA_RPC),
    [31337]: http("http://127.0.0.1:8545"),
  },
  ssr: true,
});