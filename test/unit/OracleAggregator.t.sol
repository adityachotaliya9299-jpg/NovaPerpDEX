// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase3Base} from "../Phase3Base.sol";
import {OracleAggregator} from "../../src/core/OracleAggregator.sol";

/// @title OracleAggregatorTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit tests for source combination, the deviation guard and fallback.
contract OracleAggregatorTest is Phase3Base {
    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);
    }

    /// @dev Seeds a flat TWAP over the window and refreshes the Chainlink feed.
    function _prime(uint256 clWad, uint256 twapWad) internal {
        uint256 t0 = block.timestamp;
        _twapRecord(twapWad);
        vm.warp(t0 + TWAP_WINDOW + 100);
        _twapRecord(twapWad);
        feed.updateAnswer(int256(clWad / 1e10)); // 8-decimal feed, fresh updatedAt
    }

    function _reconfigure(
        bool useCl,
        bool useTwap,
        uint256 maxDevBps,
        bool fallbackToTwap
    ) internal {
        vm.prank(admin);
        oracle.configureMarket(
            ETH_USD,
            OracleAggregator.Config({
                useChainlink: useCl,
                useTwap: useTwap,
                twapWindow: TWAP_WINDOW,
                maxDeviationBps: maxDevBps,
                fallbackToTwap: fallbackToTwap,
                configured: false
            })
        );
    }

    function test_ReturnsChainlinkWhenWithinBand() public {
        _prime(2_000e18, 2_000e18);
        assertEq(oracle.getPrice(ETH_USD), 2_000e18);
    }

    function test_ReturnsChainlinkOnSmallDeviation() public {
        _prime(2_040e18, 2_000e18); // 2% deviation, under 5% band
        assertEq(oracle.getPrice(ETH_USD), 2_040e18);
    }

    function test_RevertOnLargeDeviation() public {
        _prime(2_200e18, 2_000e18); // 10% deviation, over 5% band, no fallback
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAggregator.PriceDeviation.selector, ETH_USD, 2_200e18, 2_000e18
            )
        );
        oracle.getPrice(ETH_USD);
    }

    function test_FallbackToTwapOnLargeDeviation() public {
        _reconfigure(true, true, 500, true);
        _prime(2_200e18, 2_000e18);
        // deviates beyond band but fallback returns the TWAP
        assertEq(oracle.getPrice(ETH_USD), 2_000e18);
    }

    function test_RevertWhen_ChainlinkUnhealthyNoFallback() public {
        _prime(2_000e18, 2_000e18);
        // make the feed stale
        vm.warp(block.timestamp + CL_STALENESS + 1);
        vm.expectRevert(abi.encodeWithSelector(OracleAggregator.NoValidPrice.selector, ETH_USD));
        oracle.getPrice(ETH_USD);
    }

    function test_FallbackWhenChainlinkUnhealthy() public {
        _reconfigure(true, true, 500, true);
        _prime(2_000e18, 2_000e18);
        vm.warp(block.timestamp + CL_STALENESS + 1);
        assertEq(oracle.getPrice(ETH_USD), 2_000e18); // TWAP fallback
    }

    function test_TwapOnlyMarket() public {
        _reconfigure(false, true, 0, false);
        _prime(9_999e18, 2_500e18); // chainlink ignored entirely
        assertEq(oracle.getPrice(ETH_USD), 2_500e18);
    }

    function test_ChainlinkOnlyMarket() public {
        _reconfigure(true, false, 0, false);
        _prime(2_345e18, 1e18); // twap ignored
        assertEq(oracle.getPrice(ETH_USD), 2_345e18);
    }

    function test_RevertWhen_ChainlinkOnlyUnhealthy() public {
        _reconfigure(true, false, 0, false);
        _prime(2_000e18, 1e18);
        vm.warp(block.timestamp + CL_STALENESS + 1);
        vm.expectRevert(abi.encodeWithSelector(OracleAggregator.NoValidPrice.selector, ETH_USD));
        oracle.getPrice(ETH_USD);
    }

    function test_RevertWhen_MarketNotConfigured() public {
        bytes32 doge = keccak256("DOGE-USD");
        vm.expectRevert(abi.encodeWithSelector(OracleAggregator.MarketNotConfigured.selector, doge));
        oracle.getPrice(doge);
    }

    function test_RevertWhen_ConfigureNoSource() public {
        vm.prank(admin);
        vm.expectRevert("OA: no source");
        oracle.configureMarket(
            ETH_USD,
            OracleAggregator.Config(false, false, TWAP_WINDOW, 500, false, false)
        );
    }

    function test_RevertWhen_ConfigureZeroWindow() public {
        vm.prank(admin);
        vm.expectRevert("OA: zero window");
        oracle.configureMarket(
            ETH_USD, OracleAggregator.Config(true, true, 0, 500, false, false)
        );
    }

    function test_RevertWhen_NonGovernorConfigures() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OracleAggregator.NotGovernor.selector, alice));
        oracle.configureMarket(
            ETH_USD, OracleAggregator.Config(true, true, TWAP_WINDOW, 500, false, false)
        );
    }

    function test_LastUpdatedZeroWhenNoObservations() public view {
        assertEq(oracle.lastUpdated(keccak256("NONE-USD")), 0);
    }

    function test_LastUpdatedNonZeroAfterObservation() public {
        _twapRecord(2_000e18);
        assertEq(oracle.lastUpdated(ETH_USD), block.timestamp);
    }

    function test_RevertWhen_ConstructedWithZeroChainlink() public {
        vm.expectRevert("OA: zero chainlink");
        new OracleAggregator(address(roles), address(0), address(twap));
    }
}