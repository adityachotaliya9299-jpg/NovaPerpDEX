// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RoleManager} from "./RoleManager.sol";

/// @title EmergencyController
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Stack-wide circuit breaker. A single boolean flip, gated to GUARDIAN_ROLE,
///         that any module can consult before allowing state-changing actions.
/// @dev Deliberately minimal: one flag, two roles. Modules read {isPaused} and revert
///      if true; wiring is optional and additive (an unset reference preserves the
///      exact behavior of earlier phases). This complements — does not replace — the
///      LiquidationEngine's own pause, which guards keeper liquidation specifically;
///      this guards the trade path (open/increase/decrease) across the whole protocol.
contract EmergencyController {
    RoleManager public immutable roles;

    /// @notice True when the protocol-wide circuit breaker is engaged.
    bool public paused;

    event Paused(address indexed guardian);
    event Unpaused(address indexed guardian);

    error NotGuardian(address caller);
    error NotGovernor(address caller);

    modifier onlyGuardian() {
        if (!roles.hasRole(roles.GUARDIAN_ROLE(), msg.sender)) revert NotGuardian(msg.sender);
        _;
    }

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager) {
        require(roleManager != address(0), "EC: zero roles");
        roles = RoleManager(roleManager);
    }

    /// @notice Engages the circuit breaker. GUARDIAN_ROLE-only.
    function pause() external onlyGuardian {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Releases the circuit breaker. GOVERNOR_ROLE-only (deliberately a higher
    ///         bar than pausing: any guardian can stop the protocol, but resuming is a
    ///         governance decision).
    function unpause() external onlyGovernor {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Whether the protocol-wide circuit breaker is engaged.
    function isPaused() external view returns (bool) {
        return paused;
    }
}