// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase4Base} from "../Phase4Base.sol";
import {CollateralVault} from "../../src/core/CollateralVault.sol";

/// @title CollateralVaultLiquidationTest
/// @notice Guard tests for the CollateralVault.liquidate wiring requirements, exercised
///         on fresh vaults with the test contract granted OPERATOR_ROLE.
contract CollateralVaultLiquidationTest is Phase4Base {
    bytes32 internal key = keccak256("alice-eth-long");

    function _freshOperatorVault() internal returns (CollateralVault cv) {
        cv = new CollateralVault(address(roles), address(vault));
        bytes32 opRole = roles.OPERATOR_ROLE();
        vm.prank(admin);
        roles.grantRole(opRole, address(this));
    }

    function test_RevertWhen_LiquidatePoolNotSet() public {
        CollateralVault cv = _freshOperatorVault();
        vm.expectRevert(CollateralVault.PoolNotSet.selector);
        cv.liquidate(alice, ETH_USD, key, 1_000e18, -int256(500e18), 100e18, liquidator);
    }

    function test_RevertWhen_LiquidateInsuranceNotSet() public {
        CollateralVault cv = _freshOperatorVault();
        vm.prank(admin);
        cv.setLiquidityPool(pool);
        vm.expectRevert(CollateralVault.InsuranceFundNotSet.selector);
        cv.liquidate(alice, ETH_USD, key, 1_000e18, -int256(500e18), 100e18, liquidator);
    }

    function test_RevertWhen_LiquidateBadDebtHandlerNotSet() public {
        CollateralVault cv = _freshOperatorVault();
        vm.startPrank(admin);
        cv.setLiquidityPool(pool);
        cv.setInsuranceFund(address(insurance));
        vm.stopPrank();
        vm.expectRevert(CollateralVault.BadDebtHandlerNotSet.selector);
        cv.liquidate(alice, ETH_USD, key, 1_000e18, -int256(500e18), 100e18, liquidator);
    }

    function test_RevertWhen_LiquidateZeroCollateral() public {
        CollateralVault cv = _freshOperatorVault();
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        cv.liquidate(alice, ETH_USD, key, 0, -int256(500e18), 100e18, liquidator);
    }

    function test_RevertWhen_NonOperatorLiquidates() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CollateralVault.NotOperator.selector, alice));
        cvault.liquidate(alice, ETH_USD, key, 1_000e18, -int256(500e18), 100e18, liquidator);
    }

    function test_RevertWhen_KeeperRewardBpsTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CollateralVault.KeeperRewardTooHigh.selector, 5_001));
        cvault.setKeeperRewardBps(5_001);
    }
}