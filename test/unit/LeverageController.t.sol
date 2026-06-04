// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Phase2Base} from "../Phase2Base.sol";
import {LeverageController} from "../../src/core/LeverageController.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title LeverageControllerTest
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Unit + fuzz tests for market registry and leverage validation.
contract LeverageControllerTest is Phase2Base {
    bytes32 internal constant BTC_USD = keccak256("BTC-USD");

    function _cfg(uint256 maxLev) internal pure returns (DataTypes.MarketConfig memory) {
        return DataTypes.MarketConfig({
            maxLeverage: maxLev,
            maintenanceMarginBps: 200,
            liquidationFeeBps: 100,
            maxOpenInterest: 1_000_000e18,
            isActive: true
        });
    }

    function test_MarketRegisteredInSetup() public view {
        assertTrue(lev.exists(ETH_USD));
        assertTrue(lev.isActive(ETH_USD));
        assertEq(lev.maxLeverage(ETH_USD), 50e18);
        assertEq(lev.marketCount(), 1);
    }

    function test_GovernorCanAddMarket() public {
        vm.prank(admin);
        lev.addMarket(BTC_USD, _cfg(25e18));
        assertTrue(lev.exists(BTC_USD));
        assertEq(lev.marketCount(), 2);
    }

    function test_RevertWhen_NonGovernorAddsMarket() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LeverageController.NotGovernor.selector, alice));
        lev.addMarket(BTC_USD, _cfg(25e18));
    }

    function test_RevertWhen_AddingDuplicateMarket() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LeverageController.MarketExists.selector, ETH_USD));
        lev.addMarket(ETH_USD, _cfg(25e18));
    }

    function test_RevertWhen_ConfigLeverageBelowOne() public {
        vm.prank(admin);
        vm.expectRevert(LeverageController.InvalidConfig.selector);
        lev.addMarket(BTC_USD, _cfg(5e17)); // 0.5x
    }

    function test_RevertWhen_ConfigMaintenanceZero() public {
        DataTypes.MarketConfig memory c = _cfg(25e18);
        c.maintenanceMarginBps = 0;
        vm.prank(admin);
        vm.expectRevert(LeverageController.InvalidConfig.selector);
        lev.addMarket(BTC_USD, c);
    }

    function test_RevertWhen_ConfigMaintenanceTooHigh() public {
        DataTypes.MarketConfig memory c = _cfg(25e18);
        c.maintenanceMarginBps = 10_000;
        vm.prank(admin);
        vm.expectRevert(LeverageController.InvalidConfig.selector);
        lev.addMarket(BTC_USD, c);
    }

    function test_RevertWhen_ConfigZeroOpenInterest() public {
        DataTypes.MarketConfig memory c = _cfg(25e18);
        c.maxOpenInterest = 0;
        vm.prank(admin);
        vm.expectRevert(LeverageController.InvalidConfig.selector);
        lev.addMarket(BTC_USD, c);
    }

    function test_GovernorCanUpdateConfig() public {
        vm.prank(admin);
        lev.setMarketConfig(ETH_USD, _cfg(20e18));
        assertEq(lev.maxLeverage(ETH_USD), 20e18);
    }

    function test_RevertWhen_UpdatingUnknownMarket() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LeverageController.MarketUnknown.selector, BTC_USD));
        lev.setMarketConfig(BTC_USD, _cfg(20e18));
    }

    function test_GovernorCanDeactivateMarket() public {
        vm.prank(admin);
        lev.setMarketActive(ETH_USD, false);
        assertFalse(lev.isActive(ETH_USD));
    }

    function test_GovernorCanSetMinCollateral() public {
        vm.prank(admin);
        lev.setMinCollateral(50e18);
        assertEq(lev.minCollateral(), 50e18);
    }

    function test_ValidatePositionPassesWithinLimits() public view {
        // size 10000, collateral 1000 => 10x, under 50x cap
        lev.validatePosition(ETH_USD, 10_000e18, 1_000e18);
    }

    function test_RevertWhen_ValidateUnknownMarket() public {
        vm.expectRevert(abi.encodeWithSelector(LeverageController.MarketUnknown.selector, BTC_USD));
        lev.validatePosition(BTC_USD, 10_000e18, 1_000e18);
    }

    function test_RevertWhen_ValidateInactiveMarket() public {
        vm.prank(admin);
        lev.setMarketActive(ETH_USD, false);
        vm.expectRevert(abi.encodeWithSelector(LeverageController.MarketInactive.selector, ETH_USD));
        lev.validatePosition(ETH_USD, 10_000e18, 1_000e18);
    }

    function test_RevertWhen_ValidateZeroSize() public {
        vm.expectRevert(LeverageController.ZeroSize.selector);
        lev.validatePosition(ETH_USD, 0, 1_000e18);
    }

    function test_RevertWhen_CollateralBelowMin() public {
        vm.expectRevert(
            abi.encodeWithSelector(LeverageController.CollateralTooLow.selector, 5e18, MIN_COLLATERAL)
        );
        lev.validatePosition(ETH_USD, 100e18, 5e18);
    }

    function test_RevertWhen_LeverageTooHigh() public {
        // size 100000, collateral 1000 => 100x > 50x
        vm.expectRevert(
            abi.encodeWithSelector(LeverageController.LeverageTooHigh.selector, 100e18, 50e18)
        );
        lev.validatePosition(ETH_USD, 100_000e18, 1_000e18);
    }

    function test_ValidateAtExactMaxLeverage() public view {
        // 50000 / 1000 = 50x exactly
        lev.validatePosition(ETH_USD, 50_000e18, 1_000e18);
    }

    function test_GetMarketConfigReturnsAll() public view {
        DataTypes.MarketConfig memory c = lev.getMarketConfig(ETH_USD);
        assertEq(c.maxLeverage, 50e18);
        assertEq(c.maintenanceMarginBps, 200);
        assertEq(c.maxOpenInterest, 10_000_000e18);
        assertTrue(c.isActive);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("LC: zero roles");
        new LeverageController(address(0), MIN_COLLATERAL);
    }

    function testFuzz_ValidateLeverageBoundary(uint256 size, uint256 collateral) public {
        collateral = bound(collateral, MIN_COLLATERAL, 1_000_000e18);
        size = bound(size, 1, 100_000_000e18);
        uint256 leverage = (size * 1e18) / collateral;
        if (leverage <= 50e18 && size > 0) {
            lev.validatePosition(ETH_USD, size, collateral);
        } else {
            vm.expectRevert();
            lev.validatePosition(ETH_USD, size, collateral);
        }
    }
}
