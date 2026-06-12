// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title DataTypes
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Canonical structs, enums and constants shared across the protocol.
/// @dev Keeping these in one library guarantees a single source of truth for the
///      storage shapes used by the margin engine, liquidation engine and frontend.
library DataTypes {
    /// @notice Direction of a perpetual position.
    enum Side {
        LONG,
        SHORT
    }

    /// @notice Margin accounting mode for an account on a given market.
     enum MarginMode {
        ISOLATED,
        CROSS
    }

    /// @notice Lifecycle state of a position.
    enum PositionStatus {
        NONE,
        OPEN,
        LIQUIDATED,
        CLOSED
    }

    /// @notice A single perpetual position.
    /// @param owner The account that owns the position.
    /// @param market The market identifier (e.g. keccak256("ETH-USD")).
    /// @param side LONG or SHORT.
    /// @param size Position size denominated in USD (1e18 fixed point).
    /// @param collateral Collateral backing the position in USD (1e18 fixed point).
    /// @param entryPrice Average entry price (1e18 fixed point).
    /// @param entryFundingIndex Cumulative funding index snapshot at entry.
    /// @param lastIncreasedAt Timestamp of last size increase.
    /// @param status Lifecycle status.
    struct Position {
        address owner;
        bytes32 market;
        Side side;
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
        int256 entryFundingIndex;
        uint64 lastIncreasedAt;
        PositionStatus status;
    }

    /// @notice Per-market risk parameters.
    /// @param maxLeverage Maximum allowed leverage (1e18 fixed point, e.g. 50e18 = 50x).
    /// @param maintenanceMarginBps Maintenance margin ratio in basis points.
    /// @param liquidationFeeBps Fee paid to liquidators in basis points.
    /// @param maxOpenInterest Maximum total OI per side in USD (1e18 fixed point).
    /// @param isActive Whether the market accepts new positions.
    struct MarketConfig {
        uint256 maxLeverage;
        uint256 maintenanceMarginBps;
        uint256 liquidationFeeBps;
        uint256 maxOpenInterest;
        bool isActive;
    }
}
