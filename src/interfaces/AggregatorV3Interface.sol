// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title AggregatorV3Interface
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Minimal Chainlink price-feed interface consumed by {ChainlinkAdapter}.
/// @dev Matches Chainlink's canonical AggregatorV3Interface so production feeds
///      plug in directly. Declared locally to avoid an external dependency.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}