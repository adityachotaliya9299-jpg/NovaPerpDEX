// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOpenInterest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Read interface for per-market open interest, implemented by MarginManager.
/// @dev Lets the FundingRateEngine compute skew without a hard dependency on the
///      concrete MarginManager (avoids a deploy-time circular reference).
interface IOpenInterest {
    function longOpenInterest(bytes32 market) external view returns (uint256);

    function shortOpenInterest(bytes32 market) external view returns (uint256);
}