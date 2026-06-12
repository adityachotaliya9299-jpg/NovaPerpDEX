// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {BaseTest} from "../BaseTest.sol";
import {PriceFeed} from "../../src/core/PriceFeed.sol";

/// @title PriceFeedTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit tests for keeper-pushed prices and staleness handling.
contract PriceFeedTest is BaseTest {
    uint256 internal constant PRICE = 2_000e18;

    function test_KeeperCanSetPrice() public {
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, PRICE);
        assertEq(priceFeed.getPrice(ETH_USD), PRICE);
    }

    function test_SetPriceRecordsTimestamp() public {
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, PRICE);
        assertEq(priceFeed.lastUpdated(ETH_USD), block.timestamp);
    }

    function test_RevertWhen_NonKeeperSetsPrice() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PriceFeed.NotPriceKeeper.selector, alice));
        priceFeed.setPrice(ETH_USD, PRICE);
    }

    function test_RevertWhen_SetZeroPrice() public {
        vm.prank(keeper);
        vm.expectRevert(PriceFeed.ZeroPrice.selector);
        priceFeed.setPrice(ETH_USD, 0);
    }

    function test_RevertWhen_GetUnsetPrice() public {
        vm.expectRevert(PriceFeed.ZeroPrice.selector);
        priceFeed.getPrice(ETH_USD);
    }

    function test_RevertWhen_PriceIsStale() public {
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, PRICE);
        vm.warp(block.timestamp + STALENESS + 1);
        vm.expectRevert();
        priceFeed.getPrice(ETH_USD);
    }

    function test_PriceValidAtStalenessBoundary() public {
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, PRICE);
        vm.warp(block.timestamp + STALENESS);
        assertEq(priceFeed.getPrice(ETH_USD), PRICE);
    }

    function test_SetPriceOverwritesPrevious() public {
        vm.startPrank(keeper);
        priceFeed.setPrice(ETH_USD, PRICE);
        priceFeed.setPrice(ETH_USD, 2_500e18);
        vm.stopPrank();
        assertEq(priceFeed.getPrice(ETH_USD), 2_500e18);
    }

    function test_GovernorCanUpdateStaleness() public {
        vm.prank(admin);
        priceFeed.setStalenessThreshold(2 hours);
        assertEq(priceFeed.stalenessThreshold(), 2 hours);
    }

    function test_RevertWhen_NonGovernorUpdatesStaleness() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PriceFeed.NotGovernor.selector, alice));
        priceFeed.setStalenessThreshold(2 hours);
    }

    function test_RevertWhen_StalenessSetToZero() public {
        vm.prank(admin);
        vm.expectRevert("PriceFeed: zero staleness");
        priceFeed.setStalenessThreshold(0);
    }

    function test_LastUpdatedZeroForUnsetMarket() public view {
        assertEq(priceFeed.lastUpdated(keccak256("BTC-USD")), 0);
    }

    function test_RevertWhen_ConstructedWithZeroStaleness() public {
        vm.expectRevert("PriceFeed: zero staleness");
        new PriceFeed(address(roles), 0);
    }

    function testFuzz_SetAndGetPrice(uint256 price) public {
        price = bound(price, 1, type(uint128).max);
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, price);
        assertEq(priceFeed.getPrice(ETH_USD), price);
    }

    function testFuzz_StalenessWindow(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 30 days);
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, PRICE);
        vm.warp(block.timestamp + elapsed);
        if (elapsed <= STALENESS) {
            assertEq(priceFeed.getPrice(ETH_USD), PRICE);
        } else {
            vm.expectRevert();
            priceFeed.getPrice(ETH_USD);
        }
    }
}
