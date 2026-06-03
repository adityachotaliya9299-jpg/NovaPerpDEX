// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {Test} from "forge-std/Test.sol";
import {PositionLib} from "../../src/libraries/PositionLib.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title PositionLibTest
/// @notice Unit tests for position PnL, equity, leverage and liquidation math.
contract PositionLibTest is Test {
    function _pos(DataTypes.Side side, uint256 size, uint256 collateral, uint256 entry)
        internal
        view
        returns (DataTypes.Position memory p)
    {
        p = DataTypes.Position({
            owner: address(this),
            market: keccak256("ETH-USD"),
            side: side,
            size: size,
            collateral: collateral,
            entryPrice: entry,
            entryFundingIndex: 0,
            lastIncreasedAt: uint64(block.timestamp),
            status: DataTypes.PositionStatus.OPEN
        });
    }

    function test_LongProfitWhenPriceUp() public view {
        // size 10k, entry 2000, price 2200 (+10%) => +1000 pnl
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        assertEq(PositionLib.unrealizedPnl(p, 2_200e18), int256(1_000e18));
    }

    function test_LongLossWhenPriceDown() public view {
        // size 10k, entry 2000, price 1800 (-10%) => -1000 pnl
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        assertEq(PositionLib.unrealizedPnl(p, 1_800e18), -int256(1_000e18));
    }

    function test_ShortProfitWhenPriceDown() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.SHORT, 10_000e18, 1_000e18, 2_000e18);
        assertEq(PositionLib.unrealizedPnl(p, 1_800e18), int256(1_000e18));
    }

    function test_ShortLossWhenPriceUp() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.SHORT, 10_000e18, 1_000e18, 2_000e18);
        assertEq(PositionLib.unrealizedPnl(p, 2_200e18), -int256(1_000e18));
    }

    function test_NoPnlAtEntryPrice() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        assertEq(PositionLib.unrealizedPnl(p, 2_000e18), 0);
    }

    function test_ZeroSizePnlIsZero() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 0, 1_000e18, 2_000e18);
        assertEq(PositionLib.unrealizedPnl(p, 3_000e18), 0);
    }

    function test_EquityAddsProfit() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // +1000 profit at 2200 => equity 2000
        assertEq(PositionLib.equity(p, 2_200e18), 2_000e18);
    }

    function test_EquityFloorsAtZero() public view {
        // loss larger than collateral
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 500e18, 2_000e18);
        // -1000 at 1800 exceeds 500 collateral => equity 0
        assertEq(PositionLib.equity(p, 1_800e18), 0);
    }

    function test_LeverageComputed() public view {
        // size 10k, equity 2k => 5x
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 2_000e18, 2_000e18);
        assertEq(PositionLib.leverage(p, 2_000e18), 5e18);
    }

    function test_LeverageZeroSizeIsZero() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 0, 2_000e18, 2_000e18);
        assertEq(PositionLib.leverage(p, 2_000e18), 0);
    }

    function test_LeverageMaxWhenEquityZero() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 500e18, 2_000e18);
        assertEq(PositionLib.leverage(p, 1_800e18), type(uint256).max);
    }

    function test_NotLiquidatableWhenHealthy() public view {
        // equity 2000, size 10000, maintenance 5% => required 500. 2000 > 500 => safe
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 2_000e18, 2_000e18);
        assertFalse(PositionLib.isLiquidatable(p, 2_000e18, 500));
    }

    function test_LiquidatableWhenEquityBelowMaintenance() public view {
        // collateral 600, loss 900 at 1820 => equity ~150 (approx). required 500 => liquidatable
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 600e18, 2_000e18);
        // price 1830 => -850 pnl => equity ~ -250 -> 0, below 500 maintenance
        assertTrue(PositionLib.isLiquidatable(p, 1_830e18, 500));
    }

    function test_ZeroSizeNotLiquidatable() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 0, 600e18, 2_000e18);
        assertFalse(PositionLib.isLiquidatable(p, 1_000e18, 500));
    }

    function test_BlendedEntryPrice() public pure {
        // 10k @ 2000 + 10k @ 2200 => 2100 blended
        uint256 blended = PositionLib.blendedEntryPrice(10_000e18, 2_000e18, 10_000e18, 2_200e18);
        assertEq(blended, 2_100e18);
    }

    function test_BlendedEntryFromZero() public pure {
        uint256 blended = PositionLib.blendedEntryPrice(0, 0, 10_000e18, 2_000e18);
        assertEq(blended, 2_000e18);
    }

    function test_BlendedEntryZeroTotalIsZero() public pure {
        assertEq(PositionLib.blendedEntryPrice(0, 0, 0, 0), 0);
    }

    function testFuzz_LongShortPnlSymmetry(uint256 priceMove) public view {
        priceMove = bound(priceMove, 1e18, 4_000e18);
        DataTypes.Position memory long = _pos(DataTypes.Side.LONG, 10_000e18, 5_000e18, 2_000e18);
        DataTypes.Position memory short = _pos(DataTypes.Side.SHORT, 10_000e18, 5_000e18, 2_000e18);
        int256 lp = PositionLib.unrealizedPnl(long, priceMove);
        int256 sp = PositionLib.unrealizedPnl(short, priceMove);
        // long and short of equal size at same entry have opposite-signed pnl
        assertEq(lp, -sp);
    }

    function testFuzz_EquityNeverNegative(uint256 price) public view {
        price = bound(price, 1e18, 10_000e18);
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // equity returns uint, inherently >= 0; assert it does not revert and is bounded
        uint256 e = PositionLib.equity(p, price);
        assertLe(e, p.collateral + 10_000e18);
    }

    function testFuzz_BlendedEntryWithinBounds(uint256 p1, uint256 p2) public pure {
        p1 = bound(p1, 1e18, 100_000e18);
        p2 = bound(p2, 1e18, 100_000e18);
        uint256 blended = PositionLib.blendedEntryPrice(1_000e18, p1, 1_000e18, p2);
        uint256 lo = p1 < p2 ? p1 : p2;
        uint256 hi = p1 > p2 ? p1 : p2;
        assertGe(blended, lo);
        assertLe(blended, hi);
    }

    function testFuzz_LiquidationMonotonicInPrice(uint256 price) public view {
        // For a long, lower price can only make it more (or equally) liquidatable.
        price = bound(price, 1_000e18, 2_000e18);
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 800e18, 2_000e18);
        bool liqAtPrice = PositionLib.isLiquidatable(p, price, 500);
        bool liqAtLower = PositionLib.isLiquidatable(p, price / 2 + 1, 500);
        if (liqAtPrice) assertTrue(liqAtLower);
    }
}
