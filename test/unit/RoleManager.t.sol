// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {BaseTest} from "../BaseTest.sol";
import {RoleManager} from "../../src/core/RoleManager.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title RoleManagerTest
/// @notice Unit tests for role registry behaviour.
contract RoleManagerTest is BaseTest {
    function test_AdminHasDefaultAdminRole() public view {
        assertTrue(roles.hasRole(roles.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_AdminHasGovernorRole() public view {
        assertTrue(roles.hasRole(roles.GOVERNOR_ROLE(), admin));
        assertTrue(roles.isGovernor(admin));
    }

    function test_AdminHasGuardianRole() public view {
        assertTrue(roles.hasRole(roles.GUARDIAN_ROLE(), admin));
    }

    function test_OperatorGrantedInSetup() public view {
        assertTrue(roles.isOperator(operator));
    }

    function test_KeeperGrantedInSetup() public view {
        assertTrue(roles.hasRole(roles.PRICE_KEEPER_ROLE(), keeper));
    }

    function test_RandomAccountHasNoRoles() public view {
        assertFalse(roles.isGovernor(alice));
        assertFalse(roles.isOperator(alice));
        assertFalse(roles.isLiquidator(alice));
    }

    function test_AdminCanGrantRole() public {
        vm.prank(admin);
        roles.grantRole(roles.LIQUIDATOR_ROLE(), bob);
        assertTrue(roles.isLiquidator(bob));
    }

    function test_AdminCanRevokeRole() public {
        vm.prank(admin);
        roles.revokeRole(roles.OPERATOR_ROLE(), operator);
        assertFalse(roles.isOperator(operator));
    }

    function test_RevertWhen_NonAdminGrantsRole() public {
        vm.prank(alice);
        vm.expectRevert();
        roles.grantRole(roles.OPERATOR_ROLE(), bob);
    }

    function test_RevertWhen_ConstructedWithZeroAdmin() public {
        vm.expectRevert("RoleManager: zero admin");
        new RoleManager(address(0));
    }

    function test_RoleConstantsAreUnique() public view {
        bytes32[5] memory r = [
            roles.GOVERNOR_ROLE(),
            roles.OPERATOR_ROLE(),
            roles.LIQUIDATOR_ROLE(),
            roles.PRICE_KEEPER_ROLE(),
            roles.GUARDIAN_ROLE()
        ];
        for (uint256 i; i < r.length; i++) {
            for (uint256 j = i + 1; j < r.length; j++) {
                assertTrue(r[i] != r[j]);
            }
        }
    }

    function test_AccountCanRenounceOwnRole() public {
        vm.prank(operator);
        roles.renounceRole(roles.OPERATOR_ROLE(), operator);
        assertFalse(roles.isOperator(operator));
    }

    function testFuzz_GrantThenCheck(address account) public {
        vm.assume(account != address(0));
        vm.prank(admin);
        roles.grantRole(roles.LIQUIDATOR_ROLE(), account);
        assertTrue(roles.isLiquidator(account));
    }
}
