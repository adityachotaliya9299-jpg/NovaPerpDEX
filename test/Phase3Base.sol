// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RoleManager} from "../src/core/RoleManager.sol";
import {ChainlinkAdapter} from "../src/core/ChainlinkAdapter.sol";
import {TWAPOracle} from "../src/core/TWAPOracle.sol";
import {OracleAggregator} from "../src/core/OracleAggregator.sol";
import {FundingRateEngine} from "../src/core/FundingRateEngine.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {MockOpenInterest} from "../src/mocks/MockOpenInterest.sol";

/// @title Phase3Base
/// @notice Deploys the oracle stack (Chainlink adapter, TWAP, aggregator) and the
///         funding engine with a mock OI source, plus a mock Chainlink feed.
contract Phase3Base is Test {
    RoleManager internal roles;
    ChainlinkAdapter internal clAdapter;
    TWAPOracle internal twap;
    OracleAggregator internal oracle;
    FundingRateEngine internal funding;
    MockV3Aggregator internal feed;
    MockOpenInterest internal oi;

    address internal admin = makeAddr("admin");
    address internal keeper = makeAddr("keeper");
    address internal alice = makeAddr("alice");

    bytes32 internal constant ETH_USD = keccak256("ETH-USD");

    uint256 internal constant CL_STALENESS = 1 hours;
    uint256 internal constant TWAP_WINDOW = 30 minutes;

    function setUp() public virtual {
        vm.startPrank(admin);
        roles = new RoleManager(admin);
        roles.grantRole(roles.PRICE_KEEPER_ROLE(), keeper);

        // Chainlink: 8-decimal ETH/USD feed starting at $2000.
        feed = new MockV3Aggregator(8, 2_000e8);
        clAdapter = new ChainlinkAdapter(address(roles));
        clAdapter.setFeed(ETH_USD, address(feed), CL_STALENESS);

        twap = new TWAPOracle(address(roles));
        oracle = new OracleAggregator(address(roles), address(clAdapter), address(twap));
        oracle.configureMarket(
            ETH_USD,
            OracleAggregator.Config({
                useChainlink: true,
                useTwap: true,
                twapWindow: TWAP_WINDOW,
                maxDeviationBps: 500, // 5%
                fallbackToTwap: false,
                configured: false // set true inside configureMarket
            })
        );

        funding = new FundingRateEngine(address(roles));
        oi = new MockOpenInterest();
        funding.setOpenInterestSource(address(oi));
        funding.initializeMarket(ETH_USD, 1e12); // small per-second cap
        vm.stopPrank();
    }

    /// @notice Records a TWAP observation as the keeper.
    function _twapRecord(uint256 price) internal {
        vm.prank(keeper);
        twap.record(ETH_USD, price);
    }

    /// @notice Builds a continuous TWAP at a flat price over `duration` seconds.
    function _seedFlatTwap(uint256 price, uint256 duration, uint256 steps) internal {
        uint256 stepDt = duration / steps;
        for (uint256 i = 0; i < steps; i++) {
            _twapRecord(price);
            vm.warp(block.timestamp + stepDt);
        }
        _twapRecord(price);
    }
}