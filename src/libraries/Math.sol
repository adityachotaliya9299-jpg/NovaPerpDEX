// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Math
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Fixed-point math helpers used across the protocol.
/// @dev All USD-denominated values use WAD (1e18) precision. Basis points use 1e4.
library Math {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS_DENOMINATOR = 1e4;

    /// @notice Multiplies two WAD numbers, returning a WAD result (rounds down).
    function wmul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / WAD;
    }

    /// @notice Divides two WAD numbers, returning a WAD result (rounds down).
    /// @dev Reverts on division by zero via the EVM.
    function wdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * WAD) / b;
    }

    /// @notice Applies a basis-point fraction to a value (rounds down).
    /// @param value The base amount.
    /// @param bps_ The fraction in basis points (1e4 == 100%).
    function bps(uint256 value, uint256 bps_) internal pure returns (uint256) {
        return (value * bps_) / BPS_DENOMINATOR;
    }

    /// @notice Returns the smaller of two values.
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Returns the larger of two values.
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Absolute difference between two unsigned values.
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
