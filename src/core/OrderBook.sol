// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {MarginManager} from "./MarginManager.sol";

/// @title OrderBook
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Limit orders to open/increase a position when the mark crosses a trigger.
contract OrderBook {
    IPriceFeed public immutable priceFeed;
    MarginManager public immutable marginManager;

    struct Order {
        address account;
        bytes32 market;
        DataTypes.Side side;
        uint256 sizeDelta;
        uint256 collateralDelta;
        uint256 triggerPrice;
        bool triggerAbove;
        bool active;
    }

    mapping(uint256 => Order) public orders;
    uint256 public nextOrderId;

    event OrderPlaced(uint256 indexed orderId, address indexed account, bytes32 indexed market);
    event OrderCancelled(uint256 indexed orderId);
    event OrderExecuted(uint256 indexed orderId, uint256 executionPrice);

    error NotOrderOwner(uint256 orderId, address caller);
    error OrderNotActive(uint256 orderId);
    error TriggerNotMet(uint256 orderId, uint256 price, uint256 trigger);
    error ZeroSize();

    constructor(address priceFeed_, address marginManager_) {
        require(priceFeed_ != address(0), "OB: zero feed");
        require(marginManager_ != address(0), "OB: zero mm");
        priceFeed = IPriceFeed(priceFeed_);
        marginManager = MarginManager(marginManager_);
    }

    function placeOrder(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 triggerPrice,
        bool triggerAbove
    ) external returns (uint256 orderId) {
        if (sizeDelta == 0) revert ZeroSize();
        orderId = nextOrderId++;
        orders[orderId] = Order({
            account: msg.sender,
            market: market,
            side: side,
            sizeDelta: sizeDelta,
            collateralDelta: collateralDelta,
            triggerPrice: triggerPrice,
            triggerAbove: triggerAbove,
            active: true
        });
        emit OrderPlaced(orderId, msg.sender, market);
    }

    function cancelOrder(uint256 orderId) external {
        Order storage o = orders[orderId];
        if (!o.active) revert OrderNotActive(orderId);
        if (o.account != msg.sender) revert NotOrderOwner(orderId, msg.sender);
        o.active = false;
        emit OrderCancelled(orderId);
    }

    function executeOrder(uint256 orderId) external {
        Order memory o = orders[orderId];
        if (!o.active) revert OrderNotActive(orderId);

        uint256 price = priceFeed.getPrice(o.market);
        bool met = o.triggerAbove ? price >= o.triggerPrice : price <= o.triggerPrice;
        if (!met) revert TriggerNotMet(orderId, price, o.triggerPrice);

        orders[orderId].active = false;
        marginManager.increasePositionFor(o.account, o.market, o.side, o.sizeDelta, o.collateralDelta);
        emit OrderExecuted(orderId, price);
    }

    function isExecutable(uint256 orderId) external view returns (bool) {
        Order memory o = orders[orderId];
        if (!o.active) return false;
        uint256 price = priceFeed.getPrice(o.market);
        return o.triggerAbove ? price >= o.triggerPrice : price <= o.triggerPrice;
    }
}