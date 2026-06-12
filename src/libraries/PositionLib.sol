// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "./DataTypes.sol";
import {Math} from "./Math.sol";

/// @title PositionLib
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Pure functions describing the economics of a perpetual position.
/// @dev Stateless by design so it can be unit/fuzz tested in isolation and reused
///      by the margin, liquidation and risk engines without storage coupling.
library PositionLib {
    using Math for uint256;

    /// @notice Computes the unrealized PnL of a position given the current price.
    /// @dev For LONG: pnl = size * (current - entry) / entry.
    ///      For SHORT: pnl = size * (entry - current) / entry.
    ///      Returns a signed WAD value in USD terms.
    /// @param p The position.
    /// @param currentPrice The current mark price (WAD).
    /// @return pnl Signed unrealized PnL in USD (WAD).
    function unrealizedPnl(DataTypes.Position memory p, uint256 currentPrice)
        internal
        pure
        returns (int256 pnl)
    {
        if (p.size == 0 || p.entryPrice == 0) return 0;

        if (p.side == DataTypes.Side.LONG) {
            if (currentPrice >= p.entryPrice) {
                uint256 gain = p.size.wmul((currentPrice - p.entryPrice).wdiv(p.entryPrice));
                pnl = int256(gain);
            } else {
                uint256 loss = p.size.wmul((p.entryPrice - currentPrice).wdiv(p.entryPrice));
                pnl = -int256(loss);
            }
        } else {
            if (p.entryPrice >= currentPrice) {
                uint256 gain = p.size.wmul((p.entryPrice - currentPrice).wdiv(p.entryPrice));
                pnl = int256(gain);
            } else {
                uint256 loss = p.size.wmul((currentPrice - p.entryPrice).wdiv(p.entryPrice));
                pnl = -int256(loss);
            }
        }
    }

    /// @notice Equity = collateral + unrealized PnL, floored at zero.
    /// @param p The position.
    /// @param currentPrice The current mark price (WAD).
    /// @return equity Account equity in USD (WAD).
    function equity(DataTypes.Position memory p, uint256 currentPrice)
        internal
        pure
        returns (uint256)
    {
        int256 pnl = unrealizedPnl(p, currentPrice);
        int256 e = int256(p.collateral) + pnl;
        return e <= 0 ? 0 : uint256(e);
    }

    /// @notice Effective leverage = size / equity (WAD). Returns 0 when size is 0.
    /// @dev Reverts implicitly is avoided: when equity is 0 but size > 0 we return
    ///      type(uint256).max to signal an undercollateralized (liquidatable) state.
    function leverage(DataTypes.Position memory p, uint256 currentPrice)
        internal
        pure
        returns (uint256)
    {
        if (p.size == 0) return 0;
        uint256 e = equity(p, currentPrice);
        if (e == 0) return type(uint256).max;
        return p.size.wdiv(e);
    }

    /// @notice Returns true when the position's equity is below its maintenance margin.
    /// @param p The position.
    /// @param currentPrice The current mark price (WAD).
    /// @param maintenanceMarginBps Maintenance margin ratio in basis points.
    /// @return liquidatable Whether the position can be liquidated.
    function isLiquidatable(
        DataTypes.Position memory p,
        uint256 currentPrice,
        uint256 maintenanceMarginBps
    ) internal pure returns (bool) {
        if (p.size == 0) return false;
        uint256 e = equity(p, currentPrice);
        uint256 maintenanceRequired = p.size.bps(maintenanceMarginBps);
        return e < maintenanceRequired;
    }

    /// @notice Computes the new volume-weighted average entry price when increasing size.
    /// @param oldSize Existing size (WAD).
    /// @param oldEntry Existing entry price (WAD).
    /// @param addSize Added size (WAD).
    /// @param addPrice Execution price for the added size (WAD).
    /// @return newEntry The blended entry price (WAD).
    function blendedEntryPrice(
        uint256 oldSize,
        uint256 oldEntry,
        uint256 addSize,
        uint256 addPrice
    ) internal pure returns (uint256) {
        uint256 totalSize = oldSize + addSize;
        if (totalSize == 0) return 0;
        return (oldSize * oldEntry + addSize * addPrice) / totalSize;
    }

    /// @notice Size-weighted blend of a signed funding index when increasing a position.
    /// @dev Keeps `size * (indexNow - entryIndex)` correct across an increase.
    function blendedFundingIndex(
        uint256 oldSize,
        int256 oldIndex,
        uint256 addSize,
        int256 addIndex
    ) internal pure returns (int256) {
        uint256 totalSize = oldSize + addSize;
        if (totalSize == 0) return 0;
        return (oldIndex * int256(oldSize) + addIndex * int256(addSize)) / int256(totalSize);
    }

    /// @notice Equity after applying signed funding owed (positive => position pays).
    /// @dev equity = collateral + unrealizedPnl - fundingOwed, floored at zero.
    function equityAfterFunding(
        DataTypes.Position memory p,
        uint256 currentPrice,
        int256 fundingOwed
    ) internal pure returns (uint256) {
        int256 e = int256(p.collateral) + unrealizedPnl(p, currentPrice) - fundingOwed;
        return e <= 0 ? 0 : uint256(e);
    }

    /// @notice Liquidation check that accounts for funding owed.
    function isLiquidatableWithFunding(
        DataTypes.Position memory p,
        uint256 currentPrice,
        uint256 maintenanceMarginBps,
        int256 fundingOwed
    ) internal pure returns (bool) {
        if (p.size == 0) return false;
        uint256 e = equityAfterFunding(p, currentPrice, fundingOwed);
        return e < p.size.bps(maintenanceMarginBps);
    }
}