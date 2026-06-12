// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase3Base} from "../Phase3Base.sol";
import {TWAPOracle} from "../../src/core/TWAPOracle.sol";

/// @title TWAPOracleTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit tests for time-weighted average pricing and manipulation resistance.
contract TWAPOracleTest is Phase3Base {
    function setUp() public override {
        super.setUp();
        // Start from a large base timestamp so `now - window` never underflows.
        vm.warp(1_000_000);
    }

    function test_RevertWhen_NonKeeperRecords() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TWAPOracle.NotPriceKeeper.selector, alice));
        twap.record(ETH_USD, 2_000e18);
    }

    function test_RevertWhen_RecordZeroPrice() public {
        vm.prank(keeper);
        vm.expectRevert(TWAPOracle.ZeroPrice.selector);
        twap.record(ETH_USD, 0);
    }

    function test_ObservationCountIncrements() public {
        _twapRecord(2_000e18);
        _twapRecord(2_100e18);
        assertEq(twap.observationCount(ETH_USD), 2);
    }

    function test_RevertWhen_ConsultNoObservations() public {
        vm.expectRevert(abi.encodeWithSelector(TWAPOracle.NoObservations.selector, ETH_USD));
        twap.consult(ETH_USD, TWAP_WINDOW);
    }

    function test_FlatPriceGivesSameTwap() public {
        _twapRecord(2_000e18);
        vm.warp(block.timestamp + 100);
        _twapRecord(2_000e18);
        vm.warp(block.timestamp + 100);
        _twapRecord(2_000e18);
        assertEq(twap.consult(ETH_USD, 150), 2_000e18);
    }

    function test_StepChangeIsTimeWeighted() public {
        uint256 t0 = block.timestamp;
        _twapRecord(1_000e18); // price 1000 starts at t0
        vm.warp(t0 + 100);
        _twapRecord(2_000e18); // price 2000 starts at t0+100
        vm.warp(t0 + 200);
        _twapRecord(2_000e18); // observation at t0+200

        // window 200 covers [t0, t0+200]: 1000 for half, 2000 for half => 1500
        assertEq(twap.consult(ETH_USD, 200), 1_500e18);
    }

    function test_SpikeHasLimitedImpact() public {
        uint256 t0 = block.timestamp;
        _twapRecord(2_000e18);
        vm.warp(t0 + 1000);
        _twapRecord(2_000e18); // 2000 held for 1000s
        vm.warp(t0 + 1001);
        _twapRecord(10_000e18); // 1s spike to 10000
        vm.warp(t0 + 1002);
        _twapRecord(2_000e18);

        // Over the full ~1002s window, a 1-second 5x spike barely moves the average.
        uint256 twapPrice = twap.consult(ETH_USD, 1002);
        // weighted ~ (2000*1000 + 10000*1 + 2000*1)/1002 ≈ 2008
        assertApproxEqAbs(twapPrice, 2_008e18, 5e18);
        assertLt(twapPrice, 2_100e18); // far below the 10000 spike
    }

    function test_RevertWhen_WindowTooLong() public {
        uint256 t0 = block.timestamp;
        _twapRecord(2_000e18);
        vm.warp(t0 + 100);
        _twapRecord(2_000e18);
        // window extends before the first observation
        vm.expectRevert();
        twap.consult(ETH_USD, 500);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("TWAP: zero roles");
        new TWAPOracle(address(0));
    }

    function testFuzz_FlatPriceAnyWindow(uint256 price, uint256 window) public {
        price = bound(price, 1e18, 100_000e18);
        window = bound(window, 1, 900);
        uint256 t0 = block.timestamp;
        _twapRecord(price);
        vm.warp(t0 + 1000);
        _twapRecord(price);
        assertEq(twap.consult(ETH_USD, window), price);
    }
}