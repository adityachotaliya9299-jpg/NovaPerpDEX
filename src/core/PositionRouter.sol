// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {RoleManager} from "./RoleManager.sol";
import {MarginManager} from "./MarginManager.sol";
import {FundingRateEngine} from "./FundingRateEngine.sol";

/// @title PositionRouter
/// @author Aditya Chotaliya [adityachotaliya.xyz]  
/// @notice The recommended user entry point for trading. It refreshes funding before
///         each action so positions open/close against an up-to-date funding index,
///         then routes the trade through the {MarginManager} on the caller's behalf.
contract PositionRouter {
    RoleManager public immutable roles;
    MarginManager public immutable marginManager;

    FundingRateEngine public fundingEngine;

    event FundingEngineSet(address engine);

    error NotGovernor(address caller);
    error NoPosition();

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager, address marginManager_) {
        require(roleManager != address(0), "PR: zero roles");
        require(marginManager_ != address(0), "PR: zero mm");
        roles = RoleManager(roleManager);
        marginManager = MarginManager(marginManager_);
    }

    function setFundingEngine(address engine) external onlyGovernor {
        fundingEngine = FundingRateEngine(engine);
        emit FundingEngineSet(engine);
    }

    function increasePosition(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta
    ) external {
        _refreshFunding(market);
        marginManager.increasePositionFor(msg.sender, market, side, sizeDelta, collateralDelta);
    }

    function decreasePosition(bytes32 market, DataTypes.Side side, uint256 sizeDelta) external {
        _refreshFunding(market);
        marginManager.decreasePositionFor(msg.sender, market, side, sizeDelta);
    }

    function closePosition(bytes32 market, DataTypes.Side side) external {
        uint256 size = marginManager.getPosition(msg.sender, market, side).size;
        if (size == 0) revert NoPosition();
        _refreshFunding(market);
        marginManager.decreasePositionFor(msg.sender, market, side, size);
    }

    function _refreshFunding(bytes32 market) private {
        if (address(fundingEngine) != address(0)) {
            fundingEngine.updateFunding(market);
        }
    }
}