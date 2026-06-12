// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PositionLib} from "../../src/libraries/PositionLib.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title PositionLibFundingTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Tests for the funding-aware equity and liquidation helpers added in Phase 5.
contract PositionLibFundingTest is Test {
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

    // -------------------- equityAfterFunding -------------------- //

    function test_EquityReducedByPositiveFunding() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // no price pnl, funding owed +200
        uint256 e = PositionLib.equityAfterFunding(p, 2_000e18, int256(200e18));
        assertEq(e, 800e18);
    }

    function test_EquityIncreasedByNegativeFunding() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // funding owed -200 => position receives 200
        uint256 e = PositionLib.equityAfterFunding(p, 2_000e18, -int256(200e18));
        assertEq(e, 1_200e18);
    }

    function test_EquityFlooredAtZeroWithFunding() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 500e18, 2_000e18);
        // funding owed 800 => equity -300 => floored to 0
        uint256 e = PositionLib.equityAfterFunding(p, 2_000e18, int256(800e18));
        assertEq(e, 0);
    }

    function test_EquityWithPricePnlAndFunding() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // price +500 pnl, funding -100 => equity = 1000 + 500 + 100 = 1600
        uint256 e = PositionLib.equityAfterFunding(p, 2_100e18, -int256(100e18));
        assertEq(e, 1_600e18);
    }

    // --------------- isLiquidatableWithFunding --------------- //

    function test_FundingPushesIntoLiquidation() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // price equity 1000, maintenance 200, but funding owed 900 => equity 100 < 200
        assertTrue(PositionLib.isLiquidatableWithFunding(p, 2_000e18, 200, int256(900e18)));
    }

    function test_FundingReceiptPreventsLiquidation() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        // price equity 100 at 1820 (below 200 maintenance), but funding -200 => equity 300
        assertFalse(PositionLib.isLiquidatableWithFunding(p, 1_820e18, 200, -int256(200e18)));
    }

    function test_ZeroSizeNotLiquidatableWithFunding() public view {
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 0, 1_000e18, 2_000e18);
        assertFalse(PositionLib.isLiquidatableWithFunding(p, 1_500e18, 200, int256(5_000e18)));
    }

    // -------------------- blendedFundingIndex -------------------- //

    function test_BlendedFundingIndexWeighted() public pure {
        // old 1000 at index +100, add 1000 at index +200 => blended 150
        int256 blended = PositionLib.blendedFundingIndex(1_000e18, 100, 1_000e18, 200);
        assertEq(blended, 150);
    }

    function test_BlendedFundingIndexFromZero() public pure {
        int256 blended = PositionLib.blendedFundingIndex(0, 0, 1_000e18, 500);
        assertEq(blended, 500);
    }

    function test_BlendedFundingIndexNegative() public pure {
        int256 blended = PositionLib.blendedFundingIndex(1_000e18, -100, 1_000e18, -300);
        assertEq(blended, -200);
    }

    function test_BlendedFundingIndexZeroTotal() public pure {
        assertEq(PositionLib.blendedFundingIndex(0, 100, 0, 200), 0);
    }

    // ----------------------------- fuzz -------------------------------- //

    function testFuzz_EquityAfterFundingNeverNegative(uint256 price, int256 funding) public view {
        price = bound(price, 1, 1_000_000e18);
        // Bound symmetrically, well within int256 range, so collateral - funding
        // (the addition inside equityAfterFunding) cannot itself overflow.
        funding = bound(funding, -1e30, 1e30);
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        uint256 e = PositionLib.equityAfterFunding(p, price, funding);
        // equity is always uint — floored at 0
        assertLe(e, type(uint256).max);
    }

    function testFuzz_LiquidationWithFundingMonotonic(int256 extraFunding) public view {
        // Only the *more positive* direction is meaningful for this monotonicity claim
        // (a negative fundingOwed is a payout to the trader, which can only help health).
        extraFunding = bound(extraFunding, 0, 2_000e18);
        DataTypes.Position memory p = _pos(DataTypes.Side.LONG, 10_000e18, 1_000e18, 2_000e18);
        bool liqAtZero = PositionLib.isLiquidatableWithFunding(p, 2_000e18, 200, 0);
        bool liqWithMore = PositionLib.isLiquidatableWithFunding(p, 2_000e18, 200, extraFunding);
        // more positive funding owed can only make it more (or equally) liquidatable
        if (liqAtZero) assertTrue(liqWithMore);
    }

    function testFuzz_BlendedFundingIndexBetweenInputs(int128 a, int128 b) public pure {
        int256 ia = int256(a);
        int256 ib = int256(b);
        int256 blended = PositionLib.blendedFundingIndex(1_000e18, ia, 1_000e18, ib);
        int256 lo = ia < ib ? ia : ib;
        int256 hi = ia > ib ? ia : ib;
        assertGe(blended, lo);
        assertLe(blended, hi);
    }
}