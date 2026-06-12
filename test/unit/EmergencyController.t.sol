// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase6Base} from "../Phase6Base.sol";
import {EmergencyController} from "../../src/core/EmergencyController.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";

/// @title EmergencyControllerTest
/// @notice Tests for the protocol-wide pause flag and its effect on the trade path.
contract EmergencyControllerTest is Phase6Base {
    // ----------------------------- constructor ------------------------------ //

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("EC: zero roles");
        new EmergencyController(address(0));
    }

    function test_NotPausedInitially() public view {
        assertFalse(emergency.isPaused());
    }

    // ----------------------------- pause / unpause ------------------------------ //

    function test_GuardianCanPause() public {
        vm.prank(admin); // admin holds GUARDIAN_ROLE from RoleManager setup
        emergency.pause();
        assertTrue(emergency.isPaused());
    }

    function test_RevertWhen_NonGuardianPauses() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.NotGuardian.selector, alice));
        emergency.pause();
    }

    function test_GovernorCanUnpause() public {
        vm.prank(admin);
        emergency.pause();
        vm.prank(admin); // admin also holds GOVERNOR_ROLE
        emergency.unpause();
        assertFalse(emergency.isPaused());
    }

    function test_RevertWhen_NonGovernorUnpauses() public {
        vm.prank(admin);
        emergency.pause();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.NotGovernor.selector, alice));
        emergency.unpause();
    }

    function test_PauseEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit EmergencyController.Paused(admin);
        emergency.pause();
    }

    function test_UnpauseEmitsEvent() public {
        vm.prank(admin);
        emergency.pause();
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit EmergencyController.Unpaused(admin);
        emergency.unpause();
    }

    // ----------------------------- MarginManager wiring ------------------------------ //

    function test_EmergencyControllerWiredInSetup() public view {
        assertEq(address(mm.emergencyController()), address(emergency));
    }

    function test_GovernorCanSetEmergencyController() public {
        EmergencyController fresh = new EmergencyController(address(roles));
        vm.prank(admin);
        mm.setEmergencyController(address(fresh));
        assertEq(address(mm.emergencyController()), address(fresh));
    }

    function test_RevertWhen_NonGovernorSetsEmergencyController() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotGovernor.selector, alice));
        mm.setEmergencyController(address(0));
    }

    function test_IncreaseRevertsWhenPaused() public {
        _deposit(alice, 100_000e18);
        vm.prank(admin);
        emergency.pause();

        vm.prank(alice);
        vm.expectRevert(MarginManager.ProtocolPaused.selector);
        mm.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
    }

    function test_IncreaseSucceedsAfterUnpause() public {
        _deposit(alice, 100_000e18);
        vm.prank(admin);
        emergency.pause();
        vm.prank(admin);
        emergency.unpause();

        vm.prank(alice);
        mm.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
    }

    function test_DecreaseStillWorksWhenPaused() public {
        // Pause should block NEW risk (increase) but not de-risking (decrease/close).
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);

        vm.prank(admin);
        emergency.pause();

        vm.prank(alice);
        mm.decreasePosition(ETH_USD, LONG, 5_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 5_000e18);
    }

    function test_CloseStillWorksWhenPaused() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);

        vm.prank(admin);
        emergency.pause();

        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
    }

    function test_RouterIncreaseRevertsWhenPaused() public {
        _deposit(alice, 100_000e18);
        vm.prank(admin);
        emergency.pause();

        vm.prank(alice);
        vm.expectRevert(MarginManager.ProtocolPaused.selector);
        router.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
    }

    function test_LiquidationStillWorksWhenPaused() public {
        // The protocol-wide pause guards the TRADE path, not liquidations — an
        // unhealthy position must remain liquidatable even during an incident.
        _enableFunding();
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        vm.warp(block.timestamp + 90_000); // funding makes it liquidatable
        _setPrice(2_000e18); // re-anchor the feed's timestamp post-warp (avoids staleness)

        vm.prank(admin);
        emergency.pause();

        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
    }

    // ----------------------------- unset behaves as before ------------------------------ //

    function test_TradingWorksWithControllerUnset() public {
        vm.prank(admin);
        mm.setEmergencyController(address(0));

        _deposit(alice, 100_000e18);
        vm.prank(alice);
        mm.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
    }
}