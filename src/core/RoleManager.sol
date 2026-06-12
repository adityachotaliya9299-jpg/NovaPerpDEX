// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title RoleManager
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Central role registry for the protocol.
/// @dev Other modules inherit or query this to gate privileged actions. Using a
///      single registry keeps role definitions consistent and auditable. The
///      deployer receives DEFAULT_ADMIN_ROLE and can grant/revoke all other roles.
contract RoleManager is AccessControl {
    /// @notice Role allowed to configure markets and risk parameters.
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Role allowed to move collateral and mutate positions (margin engine, etc.).
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role allowed to trigger liquidations (liquidation engine / keepers).
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /// @notice Role allowed to push prices to the oracle.
    bytes32 public constant PRICE_KEEPER_ROLE = keccak256("PRICE_KEEPER_ROLE");

    /// @notice Role allowed to pause the protocol in emergencies.
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @param admin The address granted DEFAULT_ADMIN_ROLE and GOVERNOR_ROLE.
    constructor(address admin) {
        require(admin != address(0), "RoleManager: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);
    }

    /// @notice Convenience view: is `account` a governor?
    function isGovernor(address account) external view returns (bool) {
        return hasRole(GOVERNOR_ROLE, account);
    }

    /// @notice Convenience view: is `account` an operator?
    function isOperator(address account) external view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /// @notice Convenience view: is `account` a liquidator?
    function isLiquidator(address account) external view returns (bool) {
        return hasRole(LIQUIDATOR_ROLE, account);
    }
}
