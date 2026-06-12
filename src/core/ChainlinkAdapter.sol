// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title ChainlinkAdapter
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Wraps Chainlink price feeds, normalizing answers to WAD (1e18) USD and
///         enforcing freshness / round-completeness checks.
/// @dev Exposes both a reverting `getPrice` (for callers that want hard guarantees)
///      and a non-reverting `peek` (for the aggregator's fallback logic). Each market
///      maps to one feed with its own staleness window.
contract ChainlinkAdapter {
    uint256 internal constant WAD = 1e18;

    RoleManager public immutable roles;

    struct Feed {
        AggregatorV3Interface aggregator;
        uint256 staleAfter; // seconds
        uint8 decimals;
    }

    /// @notice market => feed config.
    mapping(bytes32 => Feed) private _feeds;

    event FeedSet(bytes32 indexed market, address aggregator, uint256 staleAfter);

    error NotGovernor(address caller);
    error FeedNotSet(bytes32 market);
    error InvalidPrice(int256 answer);
    error StalePrice(bytes32 market, uint256 updatedAt);
    error IncompleteRound(uint80 roundId, uint80 answeredInRound);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager) {
        require(roleManager != address(0), "CLA: zero roles");
        roles = RoleManager(roleManager);
    }

    /// @notice Registers or updates the Chainlink feed for a market. Governor-only.
    function setFeed(bytes32 market, address aggregator, uint256 staleAfter)
        external
        onlyGovernor
    {
        require(aggregator != address(0), "CLA: zero feed");
        require(staleAfter > 0, "CLA: zero staleness");
        uint8 dec = AggregatorV3Interface(aggregator).decimals();
        _feeds[market] = Feed(AggregatorV3Interface(aggregator), staleAfter, dec);
        emit FeedSet(market, aggregator, staleAfter);
    }

    /// @notice Returns the latest WAD price for a market, reverting on any problem.
    function getPrice(bytes32 market) external view returns (uint256) {
        Feed memory f = _feeds[market];
        if (address(f.aggregator) == address(0)) revert FeedNotSet(market);

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            f.aggregator.latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (updatedAt == 0 || block.timestamp - updatedAt > f.staleAfter) {
            revert StalePrice(market, updatedAt);
        }
        if (answeredInRound < roundId) revert IncompleteRound(roundId, answeredInRound);

        return _toWad(uint256(answer), f.decimals);
    }

    /// @notice Non-reverting price read for fallback logic.
    /// @return price The WAD price (0 if unavailable).
    /// @return ok Whether the price passed all validity checks.
    function peek(bytes32 market) external view returns (uint256 price, bool ok) {
        Feed memory f = _feeds[market];
        if (address(f.aggregator) == address(0)) return (0, false);

        try f.aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (answer <= 0) return (0, false);
            if (updatedAt == 0 || block.timestamp - updatedAt > f.staleAfter) return (0, false);
            if (answeredInRound < roundId) return (0, false);
            return (_toWad(uint256(answer), f.decimals), true);
        } catch {
            return (0, false);
        }
    }

    /// @notice Whether a feed is configured for a market.
    function hasFeed(bytes32 market) external view returns (bool) {
        return address(_feeds[market].aggregator) != address(0);
    }

    function feedAddress(bytes32 market) external view returns (address) {
        return address(_feeds[market].aggregator);
    }

    /// @dev Scales a raw feed answer with `decimals` to WAD (1e18).
    function _toWad(uint256 answer, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return answer;
        if (decimals < 18) return answer * (10 ** (18 - decimals));
        return answer / (10 ** (decimals - 18));
    }
}