// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IBadDebtHandler
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Interface the CollateralVault uses to record socialized bad debt when the
///         insurance fund cannot fully cover a liquidation shortfall.
interface IBadDebtHandler {
    function recordBadDebt(bytes32 market, uint256 amount) external;
}