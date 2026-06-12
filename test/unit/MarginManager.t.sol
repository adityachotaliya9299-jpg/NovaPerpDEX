// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase2Base} from "../Phase2Base.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";
import {LeverageController} from "../../src/core/LeverageController.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title MarginManagerTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice End-to-end unit tests for the position lifecycle: open, increase,
///         decrease, close, collateral changes, OI accounting and fees.
contract MarginManagerTest is Phase2Base {
    DataTypes.Side internal constant LONG = DataTypes.Side.LONG;
    DataTypes.Side internal constant SHORT = DataTypes.Side.SHORT;

    function _open(address who, DataTypes.Side side, uint256 size, uint256 collateral)
        internal
    {
        vm.prank(who);
        mm.increasePosition(ETH_USD, side, size, collateral);
    }

    // ----------------------------- opening ----------------------------- //

    function test_OpenLongCreatesPosition() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);

        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.size, 10_000e18);
        assertEq(p.collateral, 1_000e18);
        assertEq(p.entryPrice, START_PRICE);
        assertEq(uint8(p.status), uint8(DataTypes.PositionStatus.OPEN));
        assertEq(mm.longOpenInterest(ETH_USD), 10_000e18);
    }

    function test_OpenLocksCollateralAndFee() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        // free = 100000 - 1000 collateral - 10 fee
        assertEq(vault.balanceOf(alice), 100_000e18 - 1_010e18);
        assertEq(vault.lockedOf(alice), 1_000e18);
        assertEq(fees.totalFees(), 10e18);
    }

    function test_OpenShortTracksShortOI() public {
        _deposit(alice, 100_000e18);
        _open(alice, SHORT, 5_000e18, 1_000e18);
        assertEq(mm.shortOpenInterest(ETH_USD), 5_000e18);
        assertEq(mm.longOpenInterest(ETH_USD), 0);
    }

    function test_RevertWhen_OpenZeroSize() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        vm.expectRevert(MarginManager.ZeroSize.selector);
        mm.increasePosition(ETH_USD, LONG, 0, 1_000e18);
    }

    function test_RevertWhen_OpenLeverageTooHigh() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(LeverageController.LeverageTooHigh.selector, 100e18, 50e18)
        );
        mm.increasePosition(ETH_USD, LONG, 100_000e18, 1_000e18);
    }

    function test_RevertWhen_OpenBelowMinCollateral() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(LeverageController.CollateralTooLow.selector, 5e18, MIN_COLLATERAL)
        );
        mm.increasePosition(ETH_USD, LONG, 100e18, 5e18);
    }

    // ---------------------------- increasing --------------------------- //

    function test_IncreaseBlendsEntryPrice() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        _setPrice(3_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);

        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.size, 20_000e18);
        assertEq(p.collateral, 2_000e18);
        // blended: (10000*2000 + 10000*3000)/20000 = 2500
        assertEq(p.entryPrice, 2_500e18);
    }

    function test_IncreaseAddsToOpenInterest() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        _open(alice, LONG, 5_000e18, 1_000e18);
        assertEq(mm.longOpenInterest(ETH_USD), 15_000e18);
    }

    // ---------------------------- closing ------------------------------ //

    function test_CloseAtBreakevenReturnsCollateralMinusFee() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);

        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.size, 0);
        assertEq(mm.longOpenInterest(ETH_USD), 0);
        // start 100000 - open fee 10 - close fee 10 = 99980
        assertEq(vault.balanceOf(alice), 100_000e18 - 20e18);
    }

    function test_CloseLongInProfit() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        _setPrice(2_200e18); // +10%
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);

        // pnl = +1000, fees = 10 open + 10 close = 20
        // net free = 100000 - 20 + 1000 = 100980
        assertEq(vault.balanceOf(alice), 100_000e18 - 20e18 + 1_000e18);
    }

    function test_CloseLongInLoss() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        _setPrice(1_900e18); // -5% => pnl -500
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);

        // pnl -500, fees 20 => 100000 - 20 - 500 = 99480
        assertEq(vault.balanceOf(alice), 100_000e18 - 20e18 - 500e18);
    }

    function test_CloseShortInProfit() public {
        _deposit(alice, 100_000e18);
        _open(alice, SHORT, 10_000e18, 1_000e18);
        _setPrice(1_800e18); // -10% => short profit +1000
        vm.prank(alice);
        mm.closePosition(ETH_USD, SHORT);
        assertEq(vault.balanceOf(alice), 100_000e18 - 20e18 + 1_000e18);
    }

    function test_PartialDecreaseReleasesProportionalCollateral() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 2_000e18);
        vm.prank(alice);
        mm.decreasePosition(ETH_USD, LONG, 4_000e18); // close 40%

        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.size, 6_000e18);
        // collateral reduced 40%: 2000 - 800 = 1200
        assertEq(p.collateral, 1_200e18);
        assertEq(mm.longOpenInterest(ETH_USD), 6_000e18);
    }

    function test_RevertWhen_DecreaseMoreThanSize() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MarginManager.SizeExceedsPosition.selector, 20_000e18, 10_000e18)
        );
        mm.decreasePosition(ETH_USD, LONG, 20_000e18);
    }

    function test_RevertWhen_CloseNonexistentPosition() public {
        bytes32 key = mm.positionKey(alice, ETH_USD, LONG);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NoPosition.selector, key));
        mm.closePosition(ETH_USD, LONG);
    }

    // ------------------------ collateral changes ----------------------- //

    function test_AddCollateralReducesLeverage() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18); // 10x
        vm.prank(alice);
        mm.addCollateral(ETH_USD, LONG, 1_000e18);
        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.collateral, 2_000e18);
        // leverage now 10000/2000 = 5x
        assertEq(mm.getLeverage(alice, ETH_USD, LONG), 5e18);
    }

    function test_RemoveCollateralIncreasesLeverage() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 2_000e18); // 5x
        vm.prank(alice);
        mm.removeCollateral(ETH_USD, LONG, 1_000e18);
        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.collateral, 1_000e18);
        assertEq(vault.balanceOf(alice), 100_000e18 - 10e18 - 1_000e18);
    }

    function test_RevertWhen_RemoveCollateralBreachesLeverage() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18); // 10x
        vm.prank(alice);
        // remove 900 -> collateral 100 -> 100x > 50x
        vm.expectRevert(
            abi.encodeWithSelector(LeverageController.LeverageTooHigh.selector, 100e18, 50e18)
        );
        mm.removeCollateral(ETH_USD, LONG, 900e18);
    }

    function test_RevertWhen_RemoveCollateralBreachesMin() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 1_000e18, 1_000e18); // 1x
        vm.prank(alice);
        // remove 995 -> collateral 5 < min 10
        vm.expectRevert(
            abi.encodeWithSelector(LeverageController.CollateralTooLow.selector, 5e18, MIN_COLLATERAL)
        );
        mm.removeCollateral(ETH_USD, LONG, 995e18);
    }

    // --------------------------- OI cap -------------------------------- //

    function test_RevertWhen_OpenInterestCapExceeded() public {
        // tighten the cap to 50k
        DataTypes.MarketConfig memory c = lev.getMarketConfig(ETH_USD);
        c.maxOpenInterest = 50_000e18;
        vm.prank(admin);
        lev.setMarketConfig(ETH_USD, c);

        _deposit(alice, 100_000e18);
        _open(alice, LONG, 50_000e18, 1_000e18); // exactly at cap
        assertEq(mm.longOpenInterest(ETH_USD), 50_000e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                MarginManager.OpenInterestCap.selector, ETH_USD, 50_001e18, 50_000e18
            )
        );
        mm.increasePosition(ETH_USD, LONG, 1e18, 1_000e18);
    }

    // -------------------------- margin mode ---------------------------- //

    function test_SetMarginModeToCross() public {
        vm.prank(alice);
        mm.setMarginMode(ETH_USD, DataTypes.MarginMode.CROSS);
        assertTrue(cvault.getMarginMode(alice, ETH_USD) == DataTypes.MarginMode.CROSS);
    }

    // ------------------------- independence ---------------------------- //

    function test_LongAndShortAreIndependentPositions() public {
        _deposit(alice, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        _open(alice, SHORT, 6_000e18, 1_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, SHORT).size, 6_000e18);
        assertEq(mm.longOpenInterest(ETH_USD), 10_000e18);
        assertEq(mm.shortOpenInterest(ETH_USD), 6_000e18);
    }

    function test_MultipleTradersTracked() public {
        _deposit(alice, 100_000e18);
        _deposit(bob, 100_000e18);
        _open(alice, LONG, 10_000e18, 1_000e18);
        _open(bob, LONG, 20_000e18, 2_000e18);
        assertEq(mm.longOpenInterest(ETH_USD), 30_000e18);
    }

    function test_GetLeverageZeroWhenFlat() public view {
        assertEq(mm.getLeverage(alice, ETH_USD, LONG), 0);
    }
}
