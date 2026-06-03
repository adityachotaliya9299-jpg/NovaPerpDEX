// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {Test} from "forge-std/Test.sol";
import {Math} from "../../src/libraries/Math.sol";

/// @title MathTest
/// @notice Unit + fuzz tests for the fixed-point math helpers.
contract MathTest is Test {
    using Math for uint256;

    function test_WmulBasic() public pure {
        // 2.0 * 3.0 = 6.0
        assertEq(Math.wmul(2e18, 3e18), 6e18);
    }

    function test_WmulFraction() public pure {
        // 1.0 * 0.5 = 0.5
        assertEq(Math.wmul(1e18, 5e17), 5e17);
    }

    function test_WmulByZero() public pure {
        assertEq(Math.wmul(123e18, 0), 0);
    }

    function test_WdivBasic() public pure {
        // 6.0 / 3.0 = 2.0
        assertEq(Math.wdiv(6e18, 3e18), 2e18);
    }

    function test_WdivToFraction() public pure {
        // 1.0 / 4.0 = 0.25
        assertEq(Math.wdiv(1e18, 4e18), 25e16);
    }

    function test_RevertWhen_WdivByZero() public {
        vm.expectRevert();
        this.wdivExternal(1e18, 0);
    }

    function test_BpsFullValue() public pure {
        // 100% of 1000 = 1000
        assertEq(Math.bps(1000, 1e4), 1000);
    }

    function test_BpsHalf() public pure {
        // 50% of 1000 = 500
        assertEq(Math.bps(1000, 5_000), 500);
    }

    function test_BpsOnePercent() public pure {
        // 1% of 10000 = 100
        assertEq(Math.bps(10_000, 100), 100);
    }

    function test_MinMax() public pure {
        assertEq(Math.min(3, 7), 3);
        assertEq(Math.max(3, 7), 7);
        assertEq(Math.min(5, 5), 5);
    }

    function test_AbsDiff() public pure {
        assertEq(Math.absDiff(10, 4), 6);
        assertEq(Math.absDiff(4, 10), 6);
        assertEq(Math.absDiff(8, 8), 0);
    }

    function testFuzz_WmulWdivRoundTrip(uint256 a, uint256 b) public pure {
        a = bound(a, 1e18, 1e30);
        b = bound(b, 1e18, 1e30);
        // (a * b) then / b should be close to a (within rounding)
        uint256 product = Math.wmul(a, b);
        uint256 recovered = Math.wdiv(product, b);
        // allow tiny rounding error of 1 wei scaled
        assertApproxEqAbs(recovered, a, 1e6);
    }

    function testFuzz_WmulCommutative(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 1e27);
        b = bound(b, 0, 1e27);
        assertEq(Math.wmul(a, b), Math.wmul(b, a));
    }

    function testFuzz_BpsNeverExceedsValue(uint256 value, uint256 bps_) public pure {
        value = bound(value, 0, 1e30);
        bps_ = bound(bps_, 0, 1e4);
        assertLe(Math.bps(value, bps_), value);
    }

    function testFuzz_MinMaxConsistent(uint256 a, uint256 b) public pure {
        assertLe(Math.min(a, b), Math.max(a, b));
        assertTrue(Math.min(a, b) == a || Math.min(a, b) == b);
    }

    function testFuzz_AbsDiffSymmetric(uint256 a, uint256 b) public pure {
        assertEq(Math.absDiff(a, b), Math.absDiff(b, a));
    }

    function wdivExternal(uint256 a, uint256 b) external pure returns (uint256) {
        return Math.wdiv(a, b);
    }
}
