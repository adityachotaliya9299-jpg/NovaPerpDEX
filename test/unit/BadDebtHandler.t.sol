// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase4Base} from "../Phase4Base.sol";
import {BadDebtHandler} from "../../src/core/BadDebtHandler.sol";

/// @title BadDebtHandlerTest
/// @notice Unit tests for bad-debt accounting (operator-gated record/repay).
contract BadDebtHandlerTest is Phase4Base {
    bytes32 internal constant BTC = keccak256("BTC-USD");

    function _asOperator() internal {
        // grant this test contract operator rights to call record/repay directly
        bytes32 opRole = roles.OPERATOR_ROLE();
        vm.prank(admin);
        roles.grantRole(opRole, address(this));
    }

    function test_RecordIncreasesOutstanding() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 500e18);
        assertEq(badDebt.totalBadDebt(), 500e18);
        assertEq(badDebt.badDebtByMarket(ETH_USD), 500e18);
        assertEq(badDebt.lifetimeBadDebt(ETH_USD), 500e18);
    }

    function test_RecordAccumulatesAcrossMarkets() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 500e18);
        badDebt.recordBadDebt(BTC, 300e18);
        assertEq(badDebt.totalBadDebt(), 800e18);
        assertEq(badDebt.badDebtByMarket(BTC), 300e18);
    }

    function test_RevertWhen_NonOperatorRecords() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BadDebtHandler.NotOperator.selector, alice));
        badDebt.recordBadDebt(ETH_USD, 100e18);
    }

    function test_RevertWhen_RecordZero() public {
        _asOperator();
        vm.expectRevert(BadDebtHandler.ZeroAmount.selector);
        badDebt.recordBadDebt(ETH_USD, 0);
    }

    function test_RepayReducesOutstanding() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 500e18);
        badDebt.repay(ETH_USD, 200e18);
        assertEq(badDebt.totalBadDebt(), 300e18);
        assertEq(badDebt.badDebtByMarket(ETH_USD), 300e18);
    }

    function test_RepayDoesNotReduceLifetime() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 500e18);
        badDebt.repay(ETH_USD, 500e18);
        assertEq(badDebt.badDebtByMarket(ETH_USD), 0);
        assertEq(badDebt.lifetimeBadDebt(ETH_USD), 500e18); // lifetime never decreases
    }

    function test_RevertWhen_RepayExceedsOutstanding() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 100e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                BadDebtHandler.RepayExceedsOutstanding.selector, ETH_USD, 200e18, 100e18
            )
        );
        badDebt.repay(ETH_USD, 200e18);
    }

    function test_RevertWhen_NonOperatorRepays() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 100e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BadDebtHandler.NotOperator.selector, alice));
        badDebt.repay(ETH_USD, 50e18);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("BDH: zero roles");
        new BadDebtHandler(address(0));
    }

    function test_RecordEmitsEvent() public {
        _asOperator();
        vm.expectEmit(true, false, false, true);
        emit BadDebtHandler.BadDebtRecorded(ETH_USD, 500e18, 500e18);
        badDebt.recordBadDebt(ETH_USD, 500e18);
    }

    function test_MultipleRecordsSameMarket() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 200e18);
        badDebt.recordBadDebt(ETH_USD, 300e18);
        assertEq(badDebt.badDebtByMarket(ETH_USD), 500e18);
        assertEq(badDebt.lifetimeBadDebt(ETH_USD), 500e18);
    }

    function test_RepayPartialThenFull() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 500e18);
        badDebt.repay(ETH_USD, 200e18);
        badDebt.repay(ETH_USD, 300e18);
        assertEq(badDebt.badDebtByMarket(ETH_USD), 0);
        assertEq(badDebt.totalBadDebt(), 0);
    }

    function test_RepayEmitsEvent() public {
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, 500e18);
        vm.expectEmit(true, false, false, true);
        emit BadDebtHandler.BadDebtRepaid(ETH_USD, 200e18, 300e18);
        badDebt.repay(ETH_USD, 200e18);
    }

    function testFuzz_RecordAccumulates(uint256 a, uint256 b) public {
        a = bound(a, 1, 1e30);
        b = bound(b, 1, 1e30);
        _asOperator();
        badDebt.recordBadDebt(ETH_USD, a);
        badDebt.recordBadDebt(ETH_USD, b);
        assertEq(badDebt.totalBadDebt(), a + b);
    }
}