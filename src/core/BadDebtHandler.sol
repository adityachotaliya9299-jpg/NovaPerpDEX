// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IBadDebtHandler} from "../interfaces/IBadDebtHandler.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title BadDebtHandler
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Accounts for bad debt that the insurance fund could not cover during a
///         liquidation. Recorded bad debt is socialized against LP equity in Phase 6.
/// @dev Pure accounting — it holds no funds. `recordBadDebt` is called by the
///      CollateralVault (an operator); `repay` lets later phases retire bad debt as
///      the protocol recovers (e.g. from accumulated fees or LP surplus).
contract BadDebtHandler is IBadDebtHandler {
    RoleManager public immutable roles;

    /// @notice Total outstanding bad debt across all markets (WAD USD).
    uint256 public totalBadDebt;

    /// @notice Outstanding bad debt per market (WAD USD).
    mapping(bytes32 => uint256) public badDebtByMarket;

    /// @notice Cumulative bad debt ever recorded (never decreases) per market.
    mapping(bytes32 => uint256) public lifetimeBadDebt;

    event BadDebtRecorded(bytes32 indexed market, uint256 amount, uint256 totalOutstanding);
    event BadDebtRepaid(bytes32 indexed market, uint256 amount, uint256 totalOutstanding);

    error NotOperator(address caller);
    error ZeroAmount();
    error RepayExceedsOutstanding(bytes32 market, uint256 amount, uint256 outstanding);

    modifier onlyOperator() {
        if (!roles.isOperator(msg.sender)) revert NotOperator(msg.sender);
        _;
    }

    constructor(address roleManager) {
        require(roleManager != address(0), "BDH: zero roles");
        roles = RoleManager(roleManager);
    }

    /// @inheritdoc IBadDebtHandler
    function recordBadDebt(bytes32 market, uint256 amount) external onlyOperator {
        if (amount == 0) revert ZeroAmount();
        badDebtByMarket[market] += amount;
        lifetimeBadDebt[market] += amount;
        totalBadDebt += amount;
        emit BadDebtRecorded(market, amount, totalBadDebt);
    }

    /// @notice Retires `amount` of outstanding bad debt for a market. Operator-only.
    function repay(bytes32 market, uint256 amount) external onlyOperator {
        if (amount == 0) revert ZeroAmount();
        uint256 outstanding = badDebtByMarket[market];
        if (amount > outstanding) revert RepayExceedsOutstanding(market, amount, outstanding);
        badDebtByMarket[market] = outstanding - amount;
        totalBadDebt -= amount;
        emit BadDebtRepaid(market, amount, totalBadDebt);
    }
}