# NovaPerpDEX

A fully on-chain perpetual futures DEX (GMX / dYdX style), built from first principles in Foundry with a Next.js frontend.

> Status: **Phase 1 — Foundation & Core Architecture** complete.

## What this is

A decentralized perpetuals exchange supporting margin trading, leverage, liquidations, funding rates, oracle-backed pricing and a GLP-style LP pool. The protocol is built in deliberate phases, each shipping production-grade contracts with deep unit, fuzz and invariant test coverage.

## Architecture phases

| Phase | Scope | Contracts |
|------|-------|-----------|
| 1 | Foundation & core architecture | RoleManager, Vault, PriceFeed, NovaPerpToken, libraries |
| 2 | Margin engine & leverage | MarginManager, LeverageController, CollateralVault, FeeDistributor |
| 3 | Oracle & funding rate | OracleAggregator, ChainlinkAdapter, TWAPOracle, FundingRateEngine |
| 4 | Liquidation engine | LiquidationEngine, LiquidationBot, BadDebtHandler, InsuranceFund |
| 5 | Risk management & positions | RiskManager, PositionRouter, OrderBook, StopLossManager |
| 6 | LP vault & settlement | LPVault, SettlementEngine, RewardDistributor, EmergencyController |
| 7 | Frontend & integration | Next.js 15 + wagmi v2 trading UI |

## Phase 1 contracts

- `src/core/RoleManager.sol` — central RBAC registry (governor, operator, liquidator, keeper, guardian roles).
- `src/core/Vault.sol` — single-collateral custody with free/locked accounting; operator modules lock/unlock/transfer collateral.
- `src/core/PriceFeed.sol` — keeper-pushed price source with staleness protection (replaced by an aggregator in Phase 3).
- `src/core/NovaPerpToken.sol` — capped, governor-mintable NOVA token with ERC20Permit.
- `src/libraries/DataTypes.sol` — canonical structs and enums.
- `src/libraries/Math.sol` — WAD / basis-point fixed-point helpers.
- `src/libraries/PositionLib.sol` — pure PnL, equity, leverage and liquidation math.

## Setup

```bash
# Install Foundry: https://book.getfoundry.sh/getting-started/installation
make install
make build
make test
```

## Testing

```bash
make test            # all tests
make test-fuzz       # fuzz tests only
make test-invariant  # invariant suites
make coverage        # coverage summary
make gas             # gas report
```

Phase 1 ships **98 test functions** across unit, fuzz and invariant suites (fuzz tests run 256+ iterations each).

## Tech stack

Solidity 0.8.26 · Foundry · OpenZeppelin v5 · Chainlink (Phase 3) · Next.js 15 · wagmi v2 · The Graph

## License

MIT
