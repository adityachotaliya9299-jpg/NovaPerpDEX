// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase4Base} from "../Phase4Base.sol";
import {LiquidationEngine} from "../../src/core/LiquidationEngine.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title LiquidationEngineTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice End-to-end tests for liquidation: loss routing, keeper reward, insurance
///         cover, bad-debt socialization, and engine access controls.
contract LiquidationEngineTest is Phase4Base {
    function _setMaintenance(uint256 bps) internal {
        DataTypes.MarketConfig memory c = lev.getMarketConfig(ETH_USD);
        c.maintenanceMarginBps = bps;
        vm.prank(admin);
        lev.setMarketConfig(ETH_USD, c);
    }

    // --------------------------- health checks ------------------------- //

    function test_HealthyPositionNotLiquidatable() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        assertFalse(engine.isLiquidatable(alice, ETH_USD, LONG));
    }

    function test_ProfitablePositionNotLiquidatable() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(2_200e18); // long in profit
        assertFalse(engine.isLiquidatable(alice, ETH_USD, LONG));
    }

    function test_UnderwaterPositionIsLiquidatable() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18); // equity 100 < maintenance 200
        assertTrue(engine.isLiquidatable(alice, ETH_USD, LONG));
    }

    function test_RevertWhen_LiquidateHealthy() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        vm.prank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationEngine.PositionNotLiquidatable.selector, alice, ETH_USD, LONG
            )
        );
        engine.liquidate(alice, ETH_USD, LONG);
    }

    // --------------------------- core flow ----------------------------- //

    function test_LiquidateLongRoutesLossFeeAndReward() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18); // open fee 10 already taken
        uint256 poolBefore = vault.lockedOf(pool);
        uint256 insBefore = insurance.balance();

        _setPrice(1_820e18); // pnl -900, equity 100, maintenance 200
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        // loss 900 -> pool ; fee 100 -> keeper 20 / insurance 80 ; nothing back to alice
        assertEq(vault.lockedOf(pool), poolBefore + 900e18);
        assertEq(vault.balanceOf(liquidator), 20e18);
        assertEq(insurance.balance(), insBefore + 80e18);
        assertEq(vault.balanceOf(alice), 100_000e18 - 1_010e18); // unchanged from post-open

        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.size, 0);
        assertEq(uint8(p.status), uint8(DataTypes.PositionStatus.LIQUIDATED));
        assertEq(mm.longOpenInterest(ETH_USD), 0);
    }

    function test_LiquidateShort() public {
        _deposit(alice, 100_000e18);
        _openShort(alice, 10_000e18, 1_000e18);
        uint256 poolBefore = vault.lockedOf(pool);

        _setPrice(2_180e18); // short pnl -900
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, SHORT);

        assertEq(vault.lockedOf(pool), poolBefore + 900e18);
        assertEq(vault.balanceOf(liquidator), 20e18);
        assertEq(mm.shortOpenInterest(ETH_USD), 0);
    }

    function test_LiquidationReturnsRemainderToTrader() public {
        _setMaintenance(500); // 5% maintenance => liquidate with surplus over the fee
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);

        _setPrice(1_880e18); // pnl -600, equity 400 < maintenance 500
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        // loss 600, fee 100 (kept 20 + ins 80), remainder 300 back to alice
        assertEq(vault.balanceOf(alice), 100_000e18 - 1_010e18 + 300e18);
        assertEq(vault.balanceOf(liquidator), 20e18);
    }

    function test_KeeperRewardZeroSendsAllFeeToInsurance() public {
        vm.prank(admin);
        cvault.setKeeperRewardBps(0);
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        uint256 insBefore = insurance.balance();

        _setPrice(1_820e18);
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        assertEq(vault.balanceOf(liquidator), 0);
        assertEq(insurance.balance(), insBefore + 100e18); // full fee to insurance
    }

    // --------------------------- bad debt ------------------------------ //

    function test_BadDebtCoveredByInsurance() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        uint256 poolBefore = vault.lockedOf(pool);
        uint256 insBefore = insurance.balance();

        _setPrice(1_700e18); // pnl -1500 > collateral 1000 => shortfall 500
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        // pool gets full collateral 1000 + insurance cover 500
        assertEq(vault.lockedOf(pool), poolBefore + 1_500e18);
        assertEq(insurance.balance(), insBefore - 500e18);
        assertEq(badDebt.totalBadDebt(), 0);
    }

    function test_BadDebtSocializedWhenInsuranceShort() public {
        // drain insurance down to 300
        vm.prank(admin);
        insurance.withdraw(INSURANCE_SEED - 300e18, admin);
        assertEq(insurance.balance(), 300e18);

        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        uint256 poolBefore = vault.lockedOf(pool);

        _setPrice(1_700e18); // shortfall 500, insurance only 300 => bad debt 200
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        assertEq(vault.lockedOf(pool), poolBefore + 1_300e18); // 1000 + 300 cover
        assertEq(insurance.balance(), 0);
        assertEq(badDebt.totalBadDebt(), 200e18);
        assertEq(badDebt.badDebtByMarket(ETH_USD), 200e18);
    }

    // --------------------------- access / pause ------------------------ //

    function test_RevertWhen_DirectLiquidateNotLiquidator() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotLiquidator.selector, alice));
        mm.liquidate(alice, ETH_USD, LONG, alice);
    }

    function test_GuardianCanPauseEngine() public {
        vm.prank(admin); // admin holds GUARDIAN_ROLE
        engine.setPaused(true);
        assertTrue(engine.paused());
    }

    function test_RevertWhen_NonGuardianPauses() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LiquidationEngine.NotGuardian.selector, alice));
        engine.setPaused(true);
    }

    function test_RevertWhen_LiquidateWhilePaused() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        vm.prank(admin);
        engine.setPaused(true);
        vm.prank(liquidator);
        vm.expectRevert(LiquidationEngine.EnginePaused.selector);
        engine.liquidate(alice, ETH_USD, LONG);
    }

    function test_LiquidateForDirectsRewardToChosenKeeper() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        // anyone may call liquidateFor, naming the reward recipient
        vm.prank(bob);
        engine.liquidateFor(alice, ETH_USD, LONG, botBeneficiary);
        assertEq(vault.balanceOf(botBeneficiary), 20e18);
    }

    function test_MultipleTradersLiquidated() public {
        _deposit(alice, 100_000e18);
        _deposit(bob, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _openLong(bob, 10_000e18, 1_000e18);
        _setPrice(1_820e18);

        vm.startPrank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
        engine.liquidate(bob, ETH_USD, LONG);
        vm.stopPrank();

        assertEq(mm.longOpenInterest(ETH_USD), 0);
        assertEq(vault.balanceOf(liquidator), 40e18); // 20 each
    }

    function test_RevertWhen_ConstructedWithZeroMarginManager() public {
        vm.expectRevert("LE: zero mm");
        new LiquidationEngine(address(roles), address(0));
    }

    // --------------------------- boundaries ---------------------------- //

    function test_ExactThresholdNotLiquidatable() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_840e18); // equity exactly 200 == maintenance; strict < means safe
        assertFalse(engine.isLiquidatable(alice, ETH_USD, LONG));
    }

    function test_JustBelowThresholdLiquidatable() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_839e18); // equity 195 < 200
        assertTrue(engine.isLiquidatable(alice, ETH_USD, LONG));
    }

    function test_FullCollateralLossNoSurplusNoBadDebt() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        uint256 poolBefore = vault.lockedOf(pool);
        uint256 insBefore = insurance.balance();

        _setPrice(1_800e18); // pnl exactly -1000 == collateral
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        assertEq(vault.lockedOf(pool), poolBefore + 1_000e18); // all collateral
        assertEq(vault.balanceOf(liquidator), 0); // no surplus for a fee
        assertEq(insurance.balance(), insBefore); // untouched
        assertEq(badDebt.totalBadDebt(), 0); // loss == collateral, no shortfall
    }

    function test_LiquidationOnlyReducesOwnSide() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _openShort(alice, 6_000e18, 1_000e18);
        _setPrice(1_820e18); // long underwater; short in profit

        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        assertEq(mm.longOpenInterest(ETH_USD), 0);
        assertEq(mm.shortOpenInterest(ETH_USD), 6_000e18); // untouched
    }

    function test_RevertWhen_LiquidateTwice() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        vm.startPrank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationEngine.PositionNotLiquidatable.selector, alice, ETH_USD, LONG
            )
        );
        engine.liquidate(alice, ETH_USD, LONG); // position already gone
        vm.stopPrank();
    }

    function test_LiquidateAfterPartialClose() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        vm.prank(alice);
        mm.decreasePosition(ETH_USD, LONG, 5_000e18); // now size 5000, collateral 500
        _setPrice(1_650e18); // deep enough to liquidate the remainder
        assertTrue(engine.isLiquidatable(alice, ETH_USD, LONG));
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
        assertEq(mm.longOpenInterest(ETH_USD), 0);
    }

    function test_EngineIsLiquidatableMatchesManager() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        assertEq(
            engine.isLiquidatable(alice, ETH_USD, LONG),
            mm.isLiquidatable(alice, ETH_USD, LONG)
        );
    }

    function test_GuardianCanUnpause() public {
        vm.startPrank(admin);
        engine.setPaused(true);
        engine.setPaused(false);
        vm.stopPrank();
        assertFalse(engine.paused());
    }

    function test_LiquidateEmitsEngineEvent() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        vm.expectEmit(true, true, true, true);
        emit LiquidationEngine.Liquidated(alice, ETH_USD, LONG, liquidator);
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
    }

    function test_RevertWhen_LiquidateForZeroKeeper() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        vm.expectRevert("LE: zero keeper");
        engine.liquidateFor(alice, ETH_USD, LONG, address(0));
    }

    // ----------------------------- fuzz -------------------------------- //

    function testFuzz_KeeperRewardMatchesBps(uint256 bps) public {
        bps = bound(bps, 0, 5_000);
        vm.prank(admin);
        cvault.setKeeperRewardBps(bps);
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18); // feeCharged == 100 (surplus == fee)
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
        // reward = 100 * bps / 1e4, and never exceeds the fee
        assertEq(vault.balanceOf(liquidator), (100e18 * bps) / 1e4);
        assertLe(vault.balanceOf(liquidator), 100e18);
    }

    function testFuzz_PositionClearedAfterLiquidation(uint256 price) public {
        price = bound(price, 1_000e18, 1_839e18); // any liquidatable mark for 10x long
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(price);
        if (!engine.isLiquidatable(alice, ETH_USD, LONG)) return;
        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
        DataTypes.Position memory p = mm.getPosition(alice, ETH_USD, LONG);
        assertEq(p.size, 0);
        assertEq(uint8(p.status), uint8(DataTypes.PositionStatus.LIQUIDATED));
    }
}