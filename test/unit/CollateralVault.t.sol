// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Phase2Base} from "../Phase2Base.sol";
import {CollateralVault} from "../../src/core/CollateralVault.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title CollateralVaultTest
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Unit tests for reservation, margin mode and settlement bookkeeping.
/// @dev Calls into CollateralVault directly while impersonating the MarginManager
///      (which holds OPERATOR_ROLE) to test the money-movement layer in isolation.
contract CollateralVaultTest is Phase2Base {
    bytes32 internal key = keccak256("alice-eth-long");

    function _asOperator() internal {
        vm.startPrank(address(mm));
    }

    function test_DefaultMarginModeIsIsolated() public view {
        assertTrue(cvault.getMarginMode(alice, ETH_USD) == DataTypes.MarginMode.ISOLATED);
    }

    function test_ReserveLocksCollateralAndChargesFee() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 10e18);
        vm.stopPrank();

        assertEq(cvault.reservedCollateral(key), 1_000e18);
        assertEq(vault.lockedOf(alice), 1_000e18);
        assertEq(vault.balanceOf(alice), 10_000e18 - 1_010e18);
        assertEq(fees.totalFees(), 10e18);
    }

    function test_RevertWhen_NonOperatorReserves() public {
        _deposit(alice, 10_000e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CollateralVault.NotOperator.selector, alice));
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 10e18);
    }

    function test_AddCollateralIncreasesReservation() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        cvault.addCollateral(alice, ETH_USD, key, 500e18);
        vm.stopPrank();
        assertEq(cvault.reservedCollateral(key), 1_500e18);
        assertEq(vault.lockedOf(alice), 1_500e18);
    }

    function test_RemoveCollateralReleasesToFree() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        cvault.removeCollateral(alice, ETH_USD, key, 400e18);
        vm.stopPrank();
        assertEq(cvault.reservedCollateral(key), 600e18);
        assertEq(vault.balanceOf(alice), 10_000e18 - 600e18);
    }

    function test_RevertWhen_RemoveMoreThanReserved() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralVault.InsufficientReserved.selector, key, 2_000e18, 1_000e18
            )
        );
        cvault.removeCollateral(alice, ETH_USD, key, 2_000e18);
        vm.stopPrank();
    }

    function test_SettleProfitPaysFromPool() public {
        _deposit(alice, 10_000e18);
        uint256 poolLockedBefore = vault.lockedOf(pool);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        // close with +500 profit, no fee
        cvault.settle(alice, ETH_USD, key, 1_000e18, int256(500e18), 0);
        vm.stopPrank();

        // alice gets collateral back (1000) + profit (500) = 1500 to free
        assertEq(vault.balanceOf(alice), 10_000e18 - 1_000e18 + 1_500e18);
        assertEq(cvault.reservedCollateral(key), 0);
        // pool paid out 500
        assertEq(vault.lockedOf(pool), poolLockedBefore - 500e18);
    }

    function test_SettleLossMovesToPool() public {
        _deposit(alice, 10_000e18);
        uint256 poolLockedBefore = vault.lockedOf(pool);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        // close with -300 loss, no fee
        cvault.settle(alice, ETH_USD, key, 1_000e18, -int256(300e18), 0);
        vm.stopPrank();

        // alice gets back collateral - loss = 700
        assertEq(vault.balanceOf(alice), 10_000e18 - 1_000e18 + 700e18);
        // pool gained 300 (re-locked)
        assertEq(vault.lockedOf(pool), poolLockedBefore + 300e18);
    }

    function test_SettleFullLossWipesCollateral() public {
        _deposit(alice, 10_000e18);
        uint256 poolLockedBefore = vault.lockedOf(pool);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        // loss exceeds collateral -> capped at collateral
        cvault.settle(alice, ETH_USD, key, 1_000e18, -int256(5_000e18), 0);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 10_000e18 - 1_000e18); // nothing returned
        assertEq(vault.lockedOf(pool), poolLockedBefore + 1_000e18);
    }

    function test_SettleChargesCloseFee() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        // breakeven close, fee 10
        cvault.settle(alice, ETH_USD, key, 1_000e18, 0, 10e18);
        vm.stopPrank();
        assertEq(fees.totalFees(), 10e18);
        // alice gets collateral - fee = 990
        assertEq(vault.balanceOf(alice), 10_000e18 - 1_000e18 + 990e18);
    }

    function test_RevertWhen_SettleWithoutPool() public {
        // fresh cvault with no pool set
        CollateralVault fresh = new CollateralVault(address(roles), address(vault));
        bytes32 opRole = roles.OPERATOR_ROLE();
        vm.prank(admin);
        roles.grantRole(opRole, address(this));
        vm.prank(admin);
        fresh.setFeeDistributor(address(fees));
        vm.expectRevert(CollateralVault.PoolNotSet.selector);
        fresh.settle(alice, ETH_USD, key, 1_000e18, 0, 0);
    }

    function test_MarginModeSwitchWhenFlat() public {
        _asOperator();
        cvault.setMarginMode(alice, ETH_USD, DataTypes.MarginMode.CROSS);
        vm.stopPrank();
        assertTrue(cvault.getMarginMode(alice, ETH_USD) == DataTypes.MarginMode.CROSS);
    }

    function test_RevertWhen_ModeSwitchWhileOpen() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralVault.ModeChangeWhileOpen.selector, alice, ETH_USD
            )
        );
        cvault.setMarginMode(alice, ETH_USD, DataTypes.MarginMode.CROSS);
        vm.stopPrank();
    }

    function test_CrossModeTracksCrossReserved() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.setMarginMode(alice, ETH_USD, DataTypes.MarginMode.CROSS);
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        vm.stopPrank();
        assertEq(cvault.crossReserved(alice), 1_000e18);
    }

    function test_IsolatedModeDoesNotTrackCross() public {
        _deposit(alice, 10_000e18);
        _asOperator();
        cvault.reserve(alice, ETH_USD, key, 1_000e18, 0);
        vm.stopPrank();
        assertEq(cvault.crossReserved(alice), 0);
        assertEq(cvault.marketReserved(alice, ETH_USD), 1_000e18);
    }

    function test_RevertWhen_ConstructedWithZeroVault() public {
        vm.expectRevert("CV: zero vault");
        new CollateralVault(address(roles), address(0));
    }
}
