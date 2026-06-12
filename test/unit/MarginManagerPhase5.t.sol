// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "../Phase5Base.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";
import {RiskManager} from "../../src/core/RiskManager.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title MarginManagerPhase5Test
/// @notice Tests for Phase 5 wiring: governor setters, router gating, and that earlier
///         behavior is preserved when optional refs are unwired.
contract MarginManagerPhase5Test is Phase5Base {
    function test_FundingEngineWiredInSetup() public view {
        assertTrue(address(mm.fundingEngine()) != address(0));
    }

    function test_RiskManagerWiredInSetup() public view {
        assertTrue(address(mm.riskManager()) != address(0));
    }

    function test_RouterAuthorizedInSetup() public view {
        assertTrue(mm.authorizedRouter(address(router)));
        assertTrue(mm.authorizedRouter(address(orderBook)));
        assertTrue(mm.authorizedRouter(address(stopLoss)));
    }

    function test_GovernorCanSetFundingEngine() public {
        vm.prank(admin);
        mm.setFundingEngine(address(0)); // unset
        assertTrue(address(mm.fundingEngine()) == address(0));
    }

    function test_GovernorCanSetRiskManager() public {
        vm.prank(admin);
        mm.setRiskManager(address(0)); // unset
        assertTrue(address(mm.riskManager()) == address(0));
    }

    function test_RevertWhen_NonGovernorSetsFunding() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotGovernor.selector, alice));
        mm.setFundingEngine(address(0));
    }

    function test_RevertWhen_NonGovernorSetsRisk() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotGovernor.selector, alice));
        mm.setRiskManager(address(0));
    }

    function test_RevertWhen_NonGovernorSetsRouter() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotGovernor.selector, alice));
        mm.setRouter(alice, true);
    }

    function test_RevertWhen_SetRouterZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("MM: zero router");
        mm.setRouter(address(0), true);
    }

    function test_DirectIncreaseStillWorks() public {
        // The non-router path should remain functional
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        mm.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
    }

    function test_DirectDecreaseStillWorks() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        mm.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        vm.prank(alice);
        mm.decreasePosition(ETH_USD, LONG, 5_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 5_000e18);
    }

    function test_RevertWhen_NonRouterCallsIncreaseFor() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotRouter.selector, alice));
        mm.increasePositionFor(alice, ETH_USD, LONG, 10_000e18, 1_000e18);
    }

    function test_RevertWhen_NonRouterCallsDecreaseFor() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotRouter.selector, alice));
        mm.decreasePositionFor(alice, ETH_USD, LONG, 5_000e18);
    }

    function test_SkewLimitBlocksTrade() public {
        // set a tight 30% skew limit
        vm.prank(admin);
        risk.setRiskConfig(
            ETH_USD,
            RiskManager.RiskConfig({
                maxSkewBps: 3_000,
                baseFeeBps: 10,
                dynamicFactorBps: 0,
                configured: false
            })
        );
        _deposit(alice, 100_000e18);
        // long into an empty book => 100% skew > 30%
        vm.prank(alice);
        vm.expectRevert();
        mm.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
    }
}