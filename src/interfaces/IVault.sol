// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IVault
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Interface for the collateral vault that custodies trader deposits.
interface IVault {
    /// @notice Emitted on a successful collateral deposit.
    event Deposited(address indexed account, address indexed token, uint256 amount);

    /// @notice Emitted on a successful collateral withdrawal.
    event Withdrawn(address indexed account, address indexed token, uint256 amount);

    /// @notice Emitted when an authorized module moves collateral between accounts.
    event CollateralTransferred(address indexed from, address indexed to, uint256 amount);

    /// @notice Deposits `amount` of the collateral token for `msg.sender`.
    function deposit(uint256 amount) external;

    /// @notice Withdraws `amount` of the collateral token to `msg.sender`.
    function withdraw(uint256 amount) external;

    /// @notice Returns the free collateral balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Total collateral held by the vault.
    function totalCollateral() external view returns (uint256);
}
