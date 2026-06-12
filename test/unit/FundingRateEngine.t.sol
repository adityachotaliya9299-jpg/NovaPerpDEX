// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase3Base} from "../Phase3Base.sol";
import {FundingRateEngine} from "../../src/core/FundingRateEngine.sol";
import {MockOpenInterest} from "../../src/mocks/MockOpenInterest.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title FundingRateEngineTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit + fuzz tests for skew-based funding rates and the cumulative index.
contract FundingRateEngineTest is Phase3Base {
    uint256 internal constant MAX_RATE = 1e12; // per second, set in Phase3Base

    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);
        funding.updateFunding(ETH_USD); // anchor lastUpdated at the base timestamp
    }

    // ----------------------------- rate -------------------------------- //

    function test_RateZeroWhenBalanced() public {
        oi.setOpenInterest(ETH_USD, 500e18, 500e18);
        assertEq(funding.currentFundingRate(ETH_USD), int256(0));
    }

    function test_RateZeroWhenNoOpenInterest() public view {
        assertEq(funding.currentFundingRate(ETH_USD), int256(0));
    }

    function test_RatePositiveWhenLongHeavy() public {
        oi.setOpenInterest(ETH_USD, 600e18, 400e18);
        // normSkew = 0.2, rate = maxRate * 0.2 = 2e11
        assertEq(funding.currentFundingRate(ETH_USD), int256(2e11));
    }

    function test_RateNegativeWhenShortHeavy() public {
        oi.setOpenInterest(ETH_USD, 400e18, 600e18);
        assertEq(funding.currentFundingRate(ETH_USD), -int256(2e11));
    }

    function test_RateCappedWhenFullyOneSided() public {
        oi.setOpenInterest(ETH_USD, 1_000e18, 0);
        assertEq(funding.currentFundingRate(ETH_USD), int256(MAX_RATE));
    }

    // ----------------------------- index ------------------------------- //

    function test_PendingIndexGrowsWithTime() public {
        oi.setOpenInterest(ETH_USD, 600e18, 400e18); // rate 2e11
        vm.warp(block.timestamp + 100);
        assertEq(funding.pendingIndex(ETH_USD), int256(2e13)); // 2e11 * 100
    }

    function test_UpdateFundingPersistsIndex() public {
        oi.setOpenInterest(ETH_USD, 600e18, 400e18);
        vm.warp(block.timestamp + 100);
        funding.updateFunding(ETH_USD);
        assertEq(funding.cumulativeIndex(ETH_USD), int256(2e13));
    }

    function test_IndexDecreasesUnderShortHeavySkew() public {
        oi.setOpenInterest(ETH_USD, 400e18, 600e18); // rate -2e11
        vm.warp(block.timestamp + 100);
        funding.updateFunding(ETH_USD);
        assertEq(funding.cumulativeIndex(ETH_USD), -int256(2e13));
    }

    // ----------------------------- owed -------------------------------- //

    function test_LongPaysWhenIndexPositive() public {
        oi.setOpenInterest(ETH_USD, 600e18, 400e18);
        vm.warp(block.timestamp + 100);
        funding.updateFunding(ETH_USD); // index = 2e13
        // owed = size * index / WAD = 10000e18 * 2e13 / 1e18 = 2e17
        int256 owed = funding.fundingOwed(ETH_USD, 10_000e18, DataTypes.Side.LONG, 0);
        assertEq(owed, int256(2e17));
    }

    function test_ShortReceivesWhenIndexPositive() public {
        oi.setOpenInterest(ETH_USD, 600e18, 400e18);
        vm.warp(block.timestamp + 100);
        funding.updateFunding(ETH_USD);
        int256 owed = funding.fundingOwed(ETH_USD, 10_000e18, DataTypes.Side.SHORT, 0);
        assertEq(owed, -int256(2e17)); // negative => receives
    }

    function test_FundingOwedZeroWhenNoDelta() public {
        oi.setOpenInterest(ETH_USD, 500e18, 500e18); // rate 0 => index flat
        int256 entry = funding.pendingIndex(ETH_USD);
        int256 owed = funding.fundingOwed(ETH_USD, 10_000e18, DataTypes.Side.LONG, entry);
        assertEq(owed, int256(0));
    }

    // ----------------------------- admin ------------------------------- //

    function test_GovernorCanSetMaxRate() public {
        vm.prank(admin);
        funding.setMaxRate(ETH_USD, 5e11);
        oi.setOpenInterest(ETH_USD, 1_000e18, 0);
        assertEq(funding.currentFundingRate(ETH_USD), int256(5e11));
    }

    function test_RevertWhen_NonGovernorInitializes() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FundingRateEngine.NotGovernor.selector, alice));
        funding.initializeMarket(keccak256("BTC-USD"), MAX_RATE);
    }

    function test_RevertWhen_NonGovernorSetsSource() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FundingRateEngine.NotGovernor.selector, alice));
        funding.setOpenInterestSource(address(oi));
    }

    function test_RevertWhen_MarketNotInitialized() public {
        FundingRateEngine fresh = new FundingRateEngine(address(roles));
        vm.prank(admin);
        fresh.setOpenInterestSource(address(oi));
        bytes32 btc = keccak256("BTC-USD");
        vm.expectRevert(abi.encodeWithSelector(FundingRateEngine.MarketNotInitialized.selector, btc));
        fresh.currentFundingRate(btc);
    }

    function test_RevertWhen_SourceNotSet() public {
        FundingRateEngine fresh = new FundingRateEngine(address(roles));
        vm.prank(admin);
        fresh.initializeMarket(ETH_USD, MAX_RATE);
        vm.expectRevert(FundingRateEngine.SourceNotSet.selector);
        fresh.currentFundingRate(ETH_USD);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("FRE: zero roles");
        new FundingRateEngine(address(0));
    }

    // ----------------------------- fuzz -------------------------------- //

    function testFuzz_RateBoundedByMax(uint256 longOi, uint256 shortOi) public {
        longOi = bound(longOi, 0, 1_000_000_000e18);
        shortOi = bound(shortOi, 0, 1_000_000_000e18);
        oi.setOpenInterest(ETH_USD, longOi, shortOi);
        int256 rate = funding.currentFundingRate(ETH_USD);
        if (rate < 0) rate = -rate;
        assertLe(uint256(rate), MAX_RATE);
    }

    function testFuzz_RateSignMatchesSkew(uint256 longOi, uint256 shortOi) public {
        longOi = bound(longOi, 1e18, 1_000_000e18);
        shortOi = bound(shortOi, 1e18, 1_000_000e18);
        oi.setOpenInterest(ETH_USD, longOi, shortOi);
        int256 rate = funding.currentFundingRate(ETH_USD);
        if (longOi >= shortOi) assertGe(rate, 0);
        else assertLe(rate, 0);
    }
}