// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {BaseTest} from "../BaseTest.sol";
import {Vault} from "../../src/core/Vault.sol";

/// @title VaultTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit tests for collateral custody, locking and transfers.
contract VaultTest is BaseTest {
    uint256 internal constant AMT = 1_000e6;

    function test_DepositIncreasesFreeBalance() public {
        _fund(alice, AMT);
        vm.prank(alice);
        vault.deposit(AMT);
        assertEq(vault.balanceOf(alice), AMT);
        assertEq(vault.totalCollateral(), AMT);
    }

    function test_DepositTransfersTokensIn() public {
        _fund(alice, AMT);
        vm.prank(alice);
        vault.deposit(AMT);
        assertEq(usdc.balanceOf(address(vault)), AMT);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_RevertWhen_DepositZero() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_WithdrawDecreasesBalance() public {
        _fund(alice, AMT);
        vm.startPrank(alice);
        vault.deposit(AMT);
        vault.withdraw(400e6);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 600e6);
        assertEq(usdc.balanceOf(alice), 400e6);
    }

    function test_RevertWhen_WithdrawMoreThanFree() public {
        _fund(alice, AMT);
        vm.startPrank(alice);
        vault.deposit(AMT);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientFree.selector, alice, AMT + 1, AMT)
        );
        vault.withdraw(AMT + 1);
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawZero() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.withdraw(0);
    }

    function test_LockMovesFreeToLocked() public {
        _depositAlice(AMT);
        vm.prank(operator);
        vault.lock(alice, 300e6);
        assertEq(vault.balanceOf(alice), 700e6);
        assertEq(vault.lockedOf(alice), 300e6);
        assertEq(vault.totalOf(alice), AMT);
    }

    function test_RevertWhen_NonOperatorLocks() public {
        _depositAlice(AMT);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.NotOperator.selector, alice));
        vault.lock(alice, 100e6);
    }

    function test_RevertWhen_LockMoreThanFree() public {
        _depositAlice(AMT);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientFree.selector, alice, AMT + 1, AMT)
        );
        vault.lock(alice, AMT + 1);
    }

    function test_UnlockMovesLockedToFree() public {
        _depositAlice(AMT);
        vm.startPrank(operator);
        vault.lock(alice, 500e6);
        vault.unlock(alice, 200e6);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 700e6);
        assertEq(vault.lockedOf(alice), 300e6);
    }

    function test_RevertWhen_UnlockMoreThanLocked() public {
        _depositAlice(AMT);
        vm.startPrank(operator);
        vault.lock(alice, 100e6);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientLocked.selector, alice, 200e6, 100e6)
        );
        vault.unlock(alice, 200e6);
        vm.stopPrank();
    }

    function test_TransferLockedMovesBetweenAccounts() public {
        _depositAlice(AMT);
        vm.startPrank(operator);
        vault.lock(alice, 600e6);
        vault.transferLocked(alice, bob, 250e6);
        vm.stopPrank();
        assertEq(vault.lockedOf(alice), 350e6);
        assertEq(vault.balanceOf(bob), 250e6);
    }

    function test_RevertWhen_TransferLockedExceedsLocked() public {
        _depositAlice(AMT);
        vm.startPrank(operator);
        vault.lock(alice, 100e6);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientLocked.selector, alice, 200e6, 100e6)
        );
        vault.transferLocked(alice, bob, 200e6);
        vm.stopPrank();
    }

    function test_RevertWhen_TransferLockedByNonOperator() public {
        _depositAlice(AMT);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.NotOperator.selector, alice));
        vault.transferLocked(alice, bob, 50e6);
    }

    function test_CannotWithdrawLockedCollateral() public {
        _depositAlice(AMT);
        vm.prank(operator);
        vault.lock(alice, 800e6);
        // only 200 free remains
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientFree.selector, alice, 300e6, 200e6)
        );
        vault.withdraw(300e6);
    }

    function test_MultipleDepositorsTracked() public {
        _fund(alice, AMT);
        _fund(bob, AMT * 2);
        vm.prank(alice);
        vault.deposit(AMT);
        vm.prank(bob);
        vault.deposit(AMT * 2);
        assertEq(vault.balanceOf(alice), AMT);
        assertEq(vault.balanceOf(bob), AMT * 2);
        assertEq(vault.totalCollateral(), AMT * 3);
    }

    function test_RevertWhen_ConstructedWithZeroToken() public {
        vm.expectRevert("Vault: zero token");
        new Vault(address(0), address(roles));
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("Vault: zero roles");
        new Vault(address(usdc), address(0));
    }

    function _depositAlice(uint256 amount) internal {
        _fund(alice, amount);
        vm.prank(alice);
        vault.deposit(amount);
    }
}
