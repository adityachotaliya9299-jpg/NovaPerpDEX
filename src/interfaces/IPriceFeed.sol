// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IPriceFeed
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Minimal price oracle interface consumed by the protocol.
/// @dev Phase 3 replaces the mock with a Chainlink + TWAP aggregator that
///      conforms to this interface, so downstream contracts never change.
interface IPriceFeed {
    /// @notice Emitted when a market price is updated.
    event PriceUpdated(bytes32 indexed market, uint256 price, uint256 timestamp);

    /// @notice Returns the latest price for a market in WAD (1e18) USD terms.
    /// @param market The market identifier.
    /// @return price The latest price (WAD).
    function getPrice(bytes32 market) external view returns (uint256 price);

    /// @notice Returns the timestamp of the latest price update for a market.
    function lastUpdated(bytes32 market) external view returns (uint256);
}
