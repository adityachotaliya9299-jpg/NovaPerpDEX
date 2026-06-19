import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { defineChain } from "viem";
import { sepolia } from "viem/chains";

/**
 * Local Anvil chain (default chain id 31337, default RPC at :8545).
 * For fast iteration: `anvil`, then run the deploy script against
 * http://127.0.0.1:8545. Instant blocks make repeated trade-flow testing
 * much faster than waiting on Sepolia's ~12s blocks.
 */
export const anvil = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
  },
  testnet: true,
});

/**
 * WalletConnect project id. RainbowKit requires one even when only injected
 * wallets (MetaMask, etc.) are used. Get a free id at
 * https://cloud.walletconnect.com if you need WalletConnect-based wallets
 * (mobile, hardware wallets over WC) — the placeholder below is fine for
 * MetaMask on either Anvil or Sepolia.
 */
const WALLETCONNECT_PROJECT_ID =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "00000000000000000000000000000000";

/**
 * Both supported chains are always registered with wagmi so the wallet
 * connector / network switcher can offer either. Which chain's CONTRACT
 * ADDRESSES are used (`lib/contracts.ts`) is controlled separately by
 * NEXT_PUBLIC_CHAIN_ID — see that file for why this is a single env-var
 * switch rather than a fully dynamic multi-chain setup.
 */
export const wagmiConfig = getDefaultConfig({
  appName: "NovaPerpDEX",
  projectId: WALLETCONNECT_PROJECT_ID,
  chains: [anvil, sepolia],
  ssr: true,
});