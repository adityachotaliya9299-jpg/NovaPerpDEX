// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase4Base} from "../Phase4Base.sol";
import {InsuranceFund} from "../../src/core/InsuranceFund.sol";

/// @title InsuranceFundTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit tests for seeding, withdrawal and balance accounting.
contract InsuranceFundTest is Phase4Base {
    function test_SeededInSetup() public view {
        assertEq(insurance.balance(), INSURANCE_SEED);
    }

    function test_GovernorCanSeedMore() public {
        vm.startPrank(admin);
        usd.mint(admin, 5_000e18);
        usd.approve(address(insurance), 5_000e18);
        insurance.seed(5_000e18);
        vm.stopPrank();
        assertEq(insurance.balance(), INSURANCE_SEED + 5_000e18);
    }

    function test_RevertWhen_NonGovernorSeeds() public {
        usd.mint(alice, 1_000e18);
        vm.startPrank(alice);
        usd.approve(address(insurance), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(InsuranceFund.NotGovernor.selector, alice));
        insurance.seed(1_000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_SeedZero() public {
        vm.prank(admin);
        vm.expectRevert(InsuranceFund.ZeroAmount.selector);
        insurance.seed(0);
    }

    function test_GovernorCanWithdraw() public {
        vm.prank(admin);
        insurance.withdraw(40_000e18, bob);
        assertEq(insurance.balance(), INSURANCE_SEED - 40_000e18);
        assertEq(usd.balanceOf(bob), 40_000e18);
    }

    function test_RevertWhen_NonGovernorWithdraws() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InsuranceFund.NotGovernor.selector, alice));
        insurance.withdraw(1e18, alice);
    }

    function test_RevertWhen_WithdrawZero() public {
        vm.prank(admin);
        vm.expectRevert(InsuranceFund.ZeroAmount.selector);
        insurance.withdraw(0, bob);
    }

    function test_RevertWhen_WithdrawToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("IF: zero to");
        insurance.withdraw(1e18, address(0));
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        vm.prank(admin);
        vm.expectRevert(); // vault unlock underflows the locked balance
        insurance.withdraw(INSURANCE_SEED + 1, bob);
    }

    function test_RevertWhen_ConstructedWithZeroVault() public {
        vm.expectRevert("IF: zero vault");
        new InsuranceFund(address(roles), address(0), address(usd));
    }

    function test_BalanceZeroForFreshFund() public {
        vm.prank(admin);
        InsuranceFund fresh = new InsuranceFund(address(roles), address(vault), address(usd));
        assertEq(fresh.balance(), 0);
    }

    function test_SeedEmitsEvent() public {
        vm.startPrank(admin);
        usd.mint(admin, 1_000e18);
        usd.approve(address(insurance), 1_000e18);
        vm.expectEmit(true, false, false, true);
        emit InsuranceFund.Seeded(admin, 1_000e18);
        insurance.seed(1_000e18);
        vm.stopPrank();
    }

    function test_WithdrawEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit InsuranceFund.Withdrawn(bob, 1_000e18);
        insurance.withdraw(1_000e18, bob);
    }
}