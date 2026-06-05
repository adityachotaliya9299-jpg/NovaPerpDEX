// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase3Base} from "../Phase3Base.sol";
import {ChainlinkAdapter} from "../../src/core/ChainlinkAdapter.sol";
import {MockV3Aggregator} from "../../src/mocks/MockV3Aggregator.sol";

/// @title ChainlinkAdapterTest
/// @notice Unit + fuzz tests for feed normalization and validity checks.
contract ChainlinkAdapterTest is Phase3Base {
    function test_FeedConfiguredInSetup() public view {
        assertTrue(clAdapter.hasFeed(ETH_USD));
        assertEq(clAdapter.feedAddress(ETH_USD), address(feed));
    }

    function test_GetPriceNormalizesTo18Decimals() public view {
        // 8-decimal feed at 2000e8 => 2000e18
        assertEq(clAdapter.getPrice(ETH_USD), 2_000e18);
    }

    function test_GetPriceReflectsUpdates() public {
        feed.updateAnswer(2_500e8);
        assertEq(clAdapter.getPrice(ETH_USD), 2_500e18);
    }

    function test_RevertWhen_FeedNotSet() public {
        bytes32 btc = keccak256("BTC-USD");
        vm.expectRevert(abi.encodeWithSelector(ChainlinkAdapter.FeedNotSet.selector, btc));
        clAdapter.getPrice(btc);
    }

    function test_RevertWhen_AnswerZeroOrNegative() public {
        feed.setRoundData(0, block.timestamp, 2, 2);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkAdapter.InvalidPrice.selector, int256(0)));
        clAdapter.getPrice(ETH_USD);
    }

    function test_RevertWhen_PriceStale() public {
        // updatedAt far in the past
        feed.setRoundData(2_000e8, block.timestamp, 2, 2);
        vm.warp(block.timestamp + CL_STALENESS + 1);
        vm.expectRevert();
        clAdapter.getPrice(ETH_USD);
    }

    function test_RevertWhen_IncompleteRound() public {
        // answeredInRound < roundId
        feed.setRoundData(2_000e8, block.timestamp, 5, 4);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkAdapter.IncompleteRound.selector, 5, 4));
        clAdapter.getPrice(ETH_USD);
    }

    function test_PeekReturnsOkWhenHealthy() public view {
        (uint256 price, bool ok) = clAdapter.peek(ETH_USD);
        assertTrue(ok);
        assertEq(price, 2_000e18);
    }

    function test_PeekReturnsNotOkWhenStale() public {
        feed.setRoundData(2_000e8, block.timestamp, 2, 2);
        vm.warp(block.timestamp + CL_STALENESS + 1);
        (uint256 price, bool ok) = clAdapter.peek(ETH_USD);
        assertFalse(ok);
        assertEq(price, 0);
    }

    function test_PeekReturnsNotOkWhenNoFeed() public view {
        (uint256 price, bool ok) = clAdapter.peek(keccak256("DOGE-USD"));
        assertFalse(ok);
        assertEq(price, 0);
    }

    function test_GovernorCanSetFeed() public {
        MockV3Aggregator newFeed = new MockV3Aggregator(8, 30_000e8);
        bytes32 btc = keccak256("BTC-USD");
        vm.prank(admin);
        clAdapter.setFeed(btc, address(newFeed), CL_STALENESS);
        assertEq(clAdapter.getPrice(btc), 30_000e18);
    }

    function test_RevertWhen_NonGovernorSetsFeed() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkAdapter.NotGovernor.selector, alice));
        clAdapter.setFeed(ETH_USD, address(feed), CL_STALENESS);
    }

    function test_NormalizationFor18DecimalFeed() public {
        MockV3Aggregator f18 = new MockV3Aggregator(18, 1_500e18);
        bytes32 m = keccak256("X-USD");
        vm.prank(admin);
        clAdapter.setFeed(m, address(f18), CL_STALENESS);
        assertEq(clAdapter.getPrice(m), 1_500e18);
    }

    function test_NormalizationFor20DecimalFeed() public {
        MockV3Aggregator f20 = new MockV3Aggregator(20, 1_500e20);
        bytes32 m = keccak256("Y-USD");
        vm.prank(admin);
        clAdapter.setFeed(m, address(f20), CL_STALENESS);
        assertEq(clAdapter.getPrice(m), 1_500e18);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("CLA: zero roles");
        new ChainlinkAdapter(address(0));
    }

    function testFuzz_NormalizationRoundTrip(uint64 rawPrice) public {
        vm.assume(rawPrice > 0);
        feed.updateAnswer(int256(uint256(rawPrice)));
        // 8-decimal feed => * 1e10
        assertEq(clAdapter.getPrice(ETH_USD), uint256(rawPrice) * 1e10);
    }
}