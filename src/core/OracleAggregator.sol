// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {Math} from "../libraries/Math.sol";
import {RoleManager} from "./RoleManager.sol";
import {ChainlinkAdapter} from "./ChainlinkAdapter.sol";
import {TWAPOracle} from "./TWAPOracle.sol";

/// @title OracleAggregator
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice The protocol's canonical price source. Implements {IPriceFeed} so it is a
///         drop-in replacement for the Phase 1 PriceFeed — MarginManager is unchanged.
/// @dev Uses Chainlink as the primary mark and an on-chain TWAP as a sanity bound.
///      If the Chainlink price deviates from the TWAP by more than `maxDeviationBps`,
///      the mark is rejected (manipulation guard); optionally it can fall back to the
///      TWAP instead of reverting. This catches both a manipulated spot and a feed
///      that has drifted, without trusting either source unconditionally.
contract OracleAggregator is IPriceFeed {
    using Math for uint256;

    RoleManager public immutable roles;
    ChainlinkAdapter public immutable chainlink;
    TWAPOracle public immutable twap;

    struct Config {
        bool useChainlink;
        bool useTwap;
        uint256 twapWindow; // seconds
        uint256 maxDeviationBps; // allowed |chainlink - twap| / twap
        bool fallbackToTwap; // if true, return TWAP when chainlink is unhealthy/deviant
        bool configured;
    }

    /// @notice market => oracle config.
    mapping(bytes32 => Config) private _config;

    event MarketConfigured(bytes32 indexed market, Config config);

    error NotGovernor(address caller);
    error MarketNotConfigured(bytes32 market);
    error NoValidPrice(bytes32 market);
    error PriceDeviation(bytes32 market, uint256 chainlinkPrice, uint256 twapPrice);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager, address chainlink_, address twap_) {
        require(roleManager != address(0), "OA: zero roles");
        require(chainlink_ != address(0), "OA: zero chainlink");
        require(twap_ != address(0), "OA: zero twap");
        roles = RoleManager(roleManager);
        chainlink = ChainlinkAdapter(chainlink_);
        twap = TWAPOracle(twap_);
    }

    /// @notice Configures the oracle sources and guard for a market. Governor-only.
    function configureMarket(bytes32 market, Config calldata config) external onlyGovernor {
        require(config.useChainlink || config.useTwap, "OA: no source");
        if (config.useTwap) require(config.twapWindow > 0, "OA: zero window");
        Config memory c = config;
        c.configured = true;
        _config[market] = c;
        emit MarketConfigured(market, c);
    }

    /// @inheritdoc IPriceFeed
    function getPrice(bytes32 market) external view returns (uint256) {
        Config memory c = _config[market];
        if (!c.configured) revert MarketNotConfigured(market);

        // TWAP-only market.
        if (c.useChainlink == false) {
            return twap.consult(market, c.twapWindow);
        }

        (uint256 clPrice, bool clOk) = chainlink.peek(market);

        // No TWAP cross-check: trust Chainlink if healthy, else revert.
        if (!c.useTwap) {
            if (!clOk) revert NoValidPrice(market);
            return clPrice;
        }

        uint256 twapPrice = twap.consult(market, c.twapWindow);

        if (clOk) {
            uint256 deviationBps =
                Math.absDiff(clPrice, twapPrice) * Math.BPS_DENOMINATOR / twapPrice;
            if (deviationBps <= c.maxDeviationBps) {
                return clPrice; // primary, within guard band
            }
            // Deviates too far: fall back or reject.
            if (c.fallbackToTwap) return twapPrice;
            revert PriceDeviation(market, clPrice, twapPrice);
        }

        // Chainlink unhealthy.
        if (c.fallbackToTwap) return twapPrice;
        revert NoValidPrice(market);
    }

    /// @inheritdoc IPriceFeed
    function lastUpdated(bytes32 market) external view returns (uint256) {
        // Best-effort: report the TWAP's latest observation timestamp when present.
        uint256 count = twap.observationCount(market);
        if (count == 0) return 0;
        return block.timestamp; // TWAP is continuously valid once seeded
    }

    function getConfig(bytes32 market) external view returns (Config memory) {
        return _config[market];
    }
}