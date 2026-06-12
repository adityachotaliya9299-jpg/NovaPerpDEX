// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {RoleManager} from "./RoleManager.sol";
import {MarginManager} from "./MarginManager.sol";

/// @title LiquidationEngine
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice The permissionless entry point for liquidating unhealthy positions.
/// @dev Holds LIQUIDATOR_ROLE so it is the sole address allowed to call
///      MarginManager.liquidate. Keepers call `liquidate` here; the caller is the
///      keeper rewarded by the settlement. Centralizing the role here lets governance
///      swap the engine without re-granting per-keeper permissions.
contract LiquidationEngine {
    RoleManager public immutable roles;
    MarginManager public immutable marginManager;

    /// @notice When true, liquidations are halted (guardian circuit-breaker).
    bool public paused;

    event Liquidated(
        address indexed account,
        bytes32 indexed market,
        DataTypes.Side side,
        address indexed keeper
    );
    event PausedSet(bool paused);

    error NotGuardian(address caller);
    error EnginePaused();
    error PositionNotLiquidatable(address account, bytes32 market, DataTypes.Side side);

    constructor(address roleManager, address marginManager_) {
        require(roleManager != address(0), "LE: zero roles");
        require(marginManager_ != address(0), "LE: zero mm");
        roles = RoleManager(roleManager);
        marginManager = MarginManager(marginManager_);
    }

    /// @notice Whether a position can currently be liquidated.
    function isLiquidatable(address account, bytes32 market, DataTypes.Side side)
        external
        view
        returns (bool)
    {
        return marginManager.isLiquidatable(account, market, side);
    }

    /// @notice Liquidates a position, rewarding the caller as the keeper.
    function liquidate(address account, bytes32 market, DataTypes.Side side) external {
        if (paused) revert EnginePaused();
        if (!marginManager.isLiquidatable(account, market, side)) {
            revert PositionNotLiquidatable(account, market, side);
        }
        marginManager.liquidate(account, market, side, msg.sender);
        emit Liquidated(account, market, side, msg.sender);
    }

    /// @notice Liquidates a position, directing the keeper reward to `keeper`.
    /// @dev Used by the LiquidationBot so the batch's keeper attribution flows through.
    function liquidateFor(address account, bytes32 market, DataTypes.Side side, address keeper)
        external
    {
        if (paused) revert EnginePaused();
        require(keeper != address(0), "LE: zero keeper");
        if (!marginManager.isLiquidatable(account, market, side)) {
            revert PositionNotLiquidatable(account, market, side);
        }
        marginManager.liquidate(account, market, side, keeper);
        emit Liquidated(account, market, side, keeper);
    }

    /// @notice Pauses or resumes liquidations. Guardian-only circuit-breaker.
    function setPaused(bool paused_) external {
        if (!roles.hasRole(roles.GUARDIAN_ROLE(), msg.sender)) revert NotGuardian(msg.sender);
        paused = paused_;
        emit PausedSet(paused_);
    }
}