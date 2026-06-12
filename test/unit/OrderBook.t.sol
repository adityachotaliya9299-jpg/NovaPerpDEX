// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "../Phase5Base.sol";
import {OrderBook} from "../../src/core/OrderBook.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title OrderBookTest
/// @notice Tests for limit order placement, cancellation, execution and edge cases.
contract OrderBookTest is Phase5Base {
    function _placeDefaultOrder() internal returns (uint256 orderId) {
        vm.prank(alice);
        orderId = orderBook.placeOrder(ETH_USD, LONG, 10_000e18, 1_000e18, 1_900e18, false);
    }

    // ----------------------------- place ------------------------------- //

    function test_PlaceOrderReturnsId() public {
        uint256 id = _placeDefaultOrder();
        assertEq(id, 0);
        assertEq(orderBook.nextOrderId(), 1);
    }

    function test_PlaceOrderStoresCorrectly() public {
        uint256 id = _placeDefaultOrder();
        (
            address account, bytes32 market, DataTypes.Side side,
            uint256 sizeDelta, uint256 collateralDelta,
            uint256 triggerPrice, bool triggerAbove, bool active
        ) = orderBook.orders(id);
        assertEq(account, alice);
        assertEq(market, ETH_USD);
        assertEq(uint8(side), uint8(LONG));
        assertEq(sizeDelta, 10_000e18);
        assertEq(collateralDelta, 1_000e18);
        assertEq(triggerPrice, 1_900e18);
        assertFalse(triggerAbove);
        assertTrue(active);
    }

    function test_RevertWhen_PlaceZeroSize() public {
        vm.prank(alice);
        vm.expectRevert(OrderBook.ZeroSize.selector);
        orderBook.placeOrder(ETH_USD, LONG, 0, 1_000e18, 1_900e18, false);
    }

    // ----------------------------- cancel ------------------------------ //

    function test_CancelOrder() public {
        uint256 id = _placeDefaultOrder();
        vm.prank(alice);
        orderBook.cancelOrder(id);
        (,,,,,,, bool active) = orderBook.orders(id);
        assertFalse(active);
    }

    function test_RevertWhen_CancelNotOwner() public {
        uint256 id = _placeDefaultOrder();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(OrderBook.NotOrderOwner.selector, id, bob));
        orderBook.cancelOrder(id);
    }

    function test_RevertWhen_CancelInactive() public {
        uint256 id = _placeDefaultOrder();
        vm.prank(alice);
        orderBook.cancelOrder(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OrderBook.OrderNotActive.selector, id));
        orderBook.cancelOrder(id);
    }

    // ----------------------------- execute ----------------------------- //

    function test_ExecuteWhenTriggerBelowMet() public {
        _deposit(alice, 100_000e18);
        uint256 id = _placeDefaultOrder(); // trigger: price <= 1900
        _setPrice(1_900e18); // exactly at trigger

        vm.prank(bob); // anyone can execute
        orderBook.executeOrder(id);

        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
        (,,,,,,, bool active) = orderBook.orders(id);
        assertFalse(active); // used up
    }

    function test_ExecuteWhenTriggerAboveMet() public {
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        uint256 id = orderBook.placeOrder(ETH_USD, LONG, 10_000e18, 1_000e18, 2_100e18, true);
        _setPrice(2_100e18);
        orderBook.executeOrder(id);
        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 10_000e18);
    }

    function test_RevertWhen_TriggerNotMet() public {
        _deposit(alice, 100_000e18);
        uint256 id = _placeDefaultOrder(); // trigger: price <= 1900
        // price is 2000 from setup => not met
        vm.expectRevert(
            abi.encodeWithSelector(OrderBook.TriggerNotMet.selector, id, 2_000e18, 1_900e18)
        );
        orderBook.executeOrder(id);
    }

    function test_RevertWhen_ExecuteInactive() public {
        uint256 id = _placeDefaultOrder();
        vm.prank(alice);
        orderBook.cancelOrder(id);
        vm.expectRevert(abi.encodeWithSelector(OrderBook.OrderNotActive.selector, id));
        orderBook.executeOrder(id);
    }

    // ----------------------------- view -------------------------------- //

    function test_IsExecutableTrue() public {
        _deposit(alice, 100_000e18);
        _placeDefaultOrder();
        _setPrice(1_900e18);
        assertTrue(orderBook.isExecutable(0));
    }

    function test_IsExecutableFalseAboveTrigger() public {
        _placeDefaultOrder();
        assertFalse(orderBook.isExecutable(0)); // price 2000 > trigger 1900
    }

    function test_IsExecutableFalseInactive() public {
        uint256 id = _placeDefaultOrder();
        vm.prank(alice);
        orderBook.cancelOrder(id);
        assertFalse(orderBook.isExecutable(id));
    }

    function test_RevertWhen_ConstructedWithZeroFeed() public {
        vm.expectRevert("OB: zero feed");
        new OrderBook(address(0), address(mm));
    }

    function test_MultipleOrdersTracked() public {
        _deposit(alice, 100_000e18);
        uint256 id1 = _placeDefaultOrder();
        vm.prank(alice);
        uint256 id2 = orderBook.placeOrder(ETH_USD, SHORT, 5_000e18, 500e18, 2_100e18, true);
        assertEq(id1, 0);
        assertEq(id2, 1);
        assertEq(orderBook.nextOrderId(), 2);
    }
}