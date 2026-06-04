// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Phase2Base} from "../Phase2Base.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title FeeDistributorTest
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Unit + fuzz tests for fee pricing, accrual and collection.
contract FeeDistributorTest is Phase2Base {
    function test_InitialConfig() public view {
        assertEq(fees.positionFeeBps(), POSITION_FEE_BPS);
        assertEq(fees.treasury(), treasury);
        assertEq(address(fees.collateralToken()), address(usd));
    }

    function test_FeeOnSize() public view {
        // 0.1% of 10000 = 10
        assertEq(fees.feeOnSize(10_000e18), 10e18);
    }

    function test_OperatorCanAccrue() public {
        vm.prank(address(mm));
        fees.accrue(ETH_USD, 5e18);
        assertEq(fees.totalFees(), 5e18);
        assertEq(fees.feesByMarket(ETH_USD), 5e18);
    }

    function test_AccrueZeroIsNoop() public {
        vm.prank(address(mm));
        fees.accrue(ETH_USD, 0);
        assertEq(fees.totalFees(), 0);
    }

    function test_RevertWhen_NonOperatorAccrues() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.NotOperator.selector, alice));
        fees.accrue(ETH_USD, 5e18);
    }

    function test_AccrueAccumulatesAcrossMarkets() public {
        bytes32 btc = keccak256("BTC-USD");
        vm.startPrank(address(mm));
        fees.accrue(ETH_USD, 3e18);
        fees.accrue(btc, 7e18);
        vm.stopPrank();
        assertEq(fees.totalFees(), 10e18);
        assertEq(fees.feesByMarket(ETH_USD), 3e18);
        assertEq(fees.feesByMarket(btc), 7e18);
    }

    function test_GovernorCanSetFee() public {
        vm.prank(admin);
        fees.setPositionFeeBps(50);
        assertEq(fees.positionFeeBps(), 50);
    }

    function test_RevertWhen_FeeAboveMax() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.FeeTooHigh.selector, 101));
        fees.setPositionFeeBps(101);
    }

    function test_RevertWhen_NonGovernorSetsFee() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.NotGovernor.selector, alice));
        fees.setPositionFeeBps(50);
    }

    function test_GovernorCanSetTreasury() public {
        vm.prank(admin);
        fees.setTreasury(bob);
        assertEq(fees.treasury(), bob);
    }

    function test_RevertWhen_TreasuryZero() public {
        vm.prank(admin);
        vm.expectRevert(FeeDistributor.ZeroTreasury.selector);
        fees.setTreasury(address(0));
    }

    function test_CollectSendsFeesToTreasury() public {
        // Simulate fees landing: deposit to fees' vault balance via a trade.
        _deposit(alice, 100_000e18);
        vm.prank(alice);
        mm.increasePosition(ETH_USD, _long(), 10_000e18, 1_000e18);
        // open fee = 10 nUSD now in fees' vault free balance
        uint256 pending = fees.pendingInVault();
        assertEq(pending, 10e18);

        vm.prank(admin);
        fees.collect(pending);
        assertEq(usd.balanceOf(treasury), pending);
        assertEq(fees.pendingInVault(), 0);
    }

    function test_RevertWhen_NonGovernorCollects() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.NotGovernor.selector, alice));
        fees.collect(1e18);
    }

    function test_RevertWhen_ConstructedWithZeroTreasury() public {
        vm.expectRevert(FeeDistributor.ZeroTreasury.selector);
        new FeeDistributor(address(roles), address(vault), address(usd), address(0), 10);
    }

    function test_RevertWhen_ConstructedFeeTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.FeeTooHigh.selector, 200));
        new FeeDistributor(address(roles), address(vault), address(usd), treasury, 200);
    }

    function testFuzz_FeeOnSizeProportional(uint256 size) public view {
        size = bound(size, 0, 1_000_000_000e18);
        uint256 expected = (size * POSITION_FEE_BPS) / 1e4;
        assertEq(fees.feeOnSize(size), expected);
    }

    function _long() internal pure returns (DataTypes.Side) {
        return DataTypes.Side.LONG;
    }
}
