// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "../Phase5Base.sol";
import {PositionRouter} from "../../src/core/PositionRouter.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title PositionRouterTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Tests for the funding-aware router entry point.
contract PositionRouterTest is Phase5Base {
    function test_IncreaseViRouter() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        router.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
    }

    function test_DecreaseViaRouter() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        router.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        vm.prank(alice);
        router.decreasePosition(ETH_USD, LONG, 5_000e18);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 5_000e18);
    }

    function test_CloseViaRouter() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        router.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        vm.prank(alice);
        router.closePosition(ETH_USD, LONG);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
    }

    function test_RouterRefreshesFunding() public {
        _enableFunding();
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        router.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
        vm.warp(block.timestamp + 100);
        // close via router should refresh funding and fold it in
        vm.prank(alice);
        router.closePosition(ETH_USD, LONG);
        // just verify it didn't revert; the FundingIntegration tests verify the math
    }

    function test_RevertWhen_CloseNoPosition() public {
        vm.prank(alice);
        vm.expectRevert(PositionRouter.NoPosition.selector);
        router.closePosition(ETH_USD, LONG);
    }

    function test_RevertWhen_ConstructedWithZeroMM() public {
        vm.expectRevert("PR: zero mm");
        new PositionRouter(address(roles), address(0));
    }

    function test_UnauthorizedRouterReverts() public {
        PositionRouter rogue = new PositionRouter(address(roles), address(mm));
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarginManager.NotRouter.selector, address(rogue)));
        rogue.increasePosition(ETH_USD, LONG, 10_000e18, 1_000e18);
    }

    function test_GovernorCanSetRouter() public {
        address newRouter = makeAddr("newRouter");
        vm.prank(admin);
        mm.setRouter(newRouter, true);
        assertTrue(mm.authorizedRouter(newRouter));
    }

    function test_GovernorCanRevokeRouter() public {
        vm.prank(admin);
        mm.setRouter(address(router), false);
        assertFalse(mm.authorizedRouter(address(router)));
    }
}