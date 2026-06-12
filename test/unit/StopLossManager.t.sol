// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "../Phase5Base.sol";
import {StopLossManager} from "../../src/core/StopLossManager.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title StopLossManagerTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Tests for stop-loss / take-profit triggers.
contract StopLossManagerTest is Phase5Base {
    function _openAndSetStop(uint256 triggerPrice, bool triggerAbove)
        internal
        returns (bytes32)
    {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        vm.prank(alice);
        stopLoss.setTrigger(ETH_USD, LONG, triggerPrice, triggerAbove);
        return keccak256(abi.encodePacked(alice, ETH_USD, uint8(LONG)));
    }

    // ----------------------------- set --------------------------------- //

    function test_SetTrigger() public {
        _openAndSetStop(1_800e18, false);
        (uint256 tp, bool above, bool active) =
            stopLoss.triggers(keccak256(abi.encodePacked(alice, ETH_USD, uint8(LONG))));
        assertEq(tp, 1_800e18);
        assertFalse(above);
        assertTrue(active);
    }

    function test_RevertWhen_SetTriggerNoPosition() public {
        vm.prank(alice);
        vm.expectRevert(StopLossManager.NoPosition.selector);
        stopLoss.setTrigger(ETH_USD, LONG, 1_800e18, false);
    }

    function test_OverwriteTrigger() public {
        _openAndSetStop(1_800e18, false);
        vm.prank(alice);
        stopLoss.setTrigger(ETH_USD, LONG, 1_700e18, false);
        (uint256 tp,,) = stopLoss.triggers(
            keccak256(abi.encodePacked(alice, ETH_USD, uint8(LONG)))
        );
        assertEq(tp, 1_700e18);
    }

    // ----------------------------- cancel ------------------------------ //

    function test_CancelTrigger() public {
        bytes32 key = _openAndSetStop(1_800e18, false);
        vm.prank(alice);
        stopLoss.cancelTrigger(ETH_USD, LONG);
        (,, bool active) = stopLoss.triggers(key);
        assertFalse(active);
    }

    function test_RevertWhen_CancelNoTrigger() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        bytes32 key = keccak256(abi.encodePacked(alice, ETH_USD, uint8(LONG)));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StopLossManager.NoTrigger.selector, key));
        stopLoss.cancelTrigger(ETH_USD, LONG);
    }

    // ----------------------------- execute ----------------------------- //

    function test_ExecuteStopLossOnLong() public {
        _openAndSetStop(1_800e18, false); // stop: close when price <= 1800
        _setPrice(1_800e18);
        vm.prank(bob); // anyone can trigger
        stopLoss.executeTrigger(alice, ETH_USD, LONG);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
    }

    function test_ExecuteTakeProfitOnLong() public {
        _openAndSetStop(2_200e18, true); // TP: close when price >= 2200
        _setPrice(2_200e18);
        stopLoss.executeTrigger(alice, ETH_USD, LONG);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
    }

    function test_RevertWhen_TriggerNotMet() public {
        _openAndSetStop(1_800e18, false);
        // price is 2000 => not at/below 1800
        vm.expectRevert(
            abi.encodeWithSelector(StopLossManager.TriggerNotMet.selector, 2_000e18, 1_800e18)
        );
        stopLoss.executeTrigger(alice, ETH_USD, LONG);
    }

    function test_RevertWhen_ExecuteNoTrigger() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        bytes32 key = keccak256(abi.encodePacked(alice, ETH_USD, uint8(LONG)));
        vm.expectRevert(abi.encodeWithSelector(StopLossManager.NoTrigger.selector, key));
        stopLoss.executeTrigger(alice, ETH_USD, LONG);
    }

    function test_RevertWhen_ExecuteNoPosition() public {
        // alice has no position but somehow a trigger exists (set then closed)
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        vm.prank(alice);
        stopLoss.setTrigger(ETH_USD, LONG, 1_800e18, false);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
        _setPrice(1_800e18);
        vm.expectRevert(StopLossManager.NoPosition.selector);
        stopLoss.executeTrigger(alice, ETH_USD, LONG);
    }

    // ----------------------------- view -------------------------------- //

    function test_IsExecutableTrue() public {
        _openAndSetStop(1_800e18, false);
        _setPrice(1_800e18);
        assertTrue(stopLoss.isExecutable(alice, ETH_USD, LONG));
    }

    function test_IsExecutableFalseAboveTrigger() public {
        _openAndSetStop(1_800e18, false);
        assertFalse(stopLoss.isExecutable(alice, ETH_USD, LONG)); // price 2000
    }

    function test_IsExecutableFalseInactive() public {
        _openAndSetStop(1_800e18, false);
        vm.prank(alice);
        stopLoss.cancelTrigger(ETH_USD, LONG);
        _setPrice(1_800e18);
        assertFalse(stopLoss.isExecutable(alice, ETH_USD, LONG));
    }

    function test_IsExecutableFalseNoPosition() public {
        _openAndSetStop(1_800e18, false);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
        _setPrice(1_800e18);
        assertFalse(stopLoss.isExecutable(alice, ETH_USD, LONG));
    }

    function test_RevertWhen_ConstructedWithZeroFeed() public {
        vm.expectRevert("SL: zero feed");
        new StopLossManager(address(0), address(mm));
    }
}