// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {MarginManager} from "./MarginManager.sol";

/// @title StopLossManager
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Stop-loss / take-profit triggers that fully close a position when the mark
///         crosses a level. One trigger per (account, market, side).
contract StopLossManager {
    IPriceFeed public immutable priceFeed;
    MarginManager public immutable marginManager;

    struct Trigger {
        uint256 triggerPrice;
        bool triggerAbove;
        bool active;
    }

    mapping(bytes32 => Trigger) public triggers;

    event TriggerSet(address indexed account, bytes32 indexed market, DataTypes.Side side, uint256 price, bool above);
    event TriggerCancelled(address indexed account, bytes32 indexed market, DataTypes.Side side);
    event TriggerExecuted(address indexed account, bytes32 indexed market, DataTypes.Side side, uint256 price);

    error NoPosition();
    error NoTrigger(bytes32 key);
    error TriggerNotMet(uint256 price, uint256 trigger);

    constructor(address priceFeed_, address marginManager_) {
        require(priceFeed_ != address(0), "SL: zero feed");
        require(marginManager_ != address(0), "SL: zero mm");
        priceFeed = IPriceFeed(priceFeed_);
        marginManager = MarginManager(marginManager_);
    }

    function _key(address account, bytes32 market, DataTypes.Side side) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, market, uint8(side)));
    }

    function setTrigger(bytes32 market, DataTypes.Side side, uint256 triggerPrice, bool triggerAbove)
        external
    {
        if (marginManager.getPosition(msg.sender, market, side).size == 0) revert NoPosition();
        triggers[_key(msg.sender, market, side)] =
            Trigger({triggerPrice: triggerPrice, triggerAbove: triggerAbove, active: true});
        emit TriggerSet(msg.sender, market, side, triggerPrice, triggerAbove);
    }

    function cancelTrigger(bytes32 market, DataTypes.Side side) external {
        bytes32 key = _key(msg.sender, market, side);
        if (!triggers[key].active) revert NoTrigger(key);
        triggers[key].active = false;
        emit TriggerCancelled(msg.sender, market, side);
    }

    function executeTrigger(address account, bytes32 market, DataTypes.Side side) external {
        bytes32 key = _key(account, market, side);
        Trigger memory t = triggers[key];
        if (!t.active) revert NoTrigger(key);

        uint256 size = marginManager.getPosition(account, market, side).size;
        if (size == 0) revert NoPosition();

        uint256 price = priceFeed.getPrice(market);
        bool met = t.triggerAbove ? price >= t.triggerPrice : price <= t.triggerPrice;
        if (!met) revert TriggerNotMet(price, t.triggerPrice);

        triggers[key].active = false;
        marginManager.decreasePositionFor(account, market, side, size);
        emit TriggerExecuted(account, market, side, price);
    }

    function isExecutable(address account, bytes32 market, DataTypes.Side side)
        external
        view
        returns (bool)
    {
        bytes32 key = _key(account, market, side);
        Trigger memory t = triggers[key];
        if (!t.active) return false;
        if (marginManager.getPosition(account, market, side).size == 0) return false;
        uint256 price = priceFeed.getPrice(market);
        return t.triggerAbove ? price >= t.triggerPrice : price <= t.triggerPrice;
    }
}