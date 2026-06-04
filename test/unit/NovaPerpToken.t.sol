// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "../BaseTest.sol";
import {NovaPerpToken} from "../../src/core/NovaPerpToken.sol";

/// @title NovaPerpTokenTest
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Unit tests for the capped, governor-mintable NOVA token.
contract NovaPerpTokenTest is BaseTest {
    function test_InitialSupplyMintedToReceiver() public view {
        assertEq(nova.balanceOf(admin), 10_000_000e18);
        assertEq(nova.totalSupply(), 10_000_000e18);
    }

    function test_MetadataCorrect() public view {
        assertEq(nova.name(), "NovaPerp");
        assertEq(nova.symbol(), "NOVA");
        assertEq(nova.decimals(), 18);
    }

    function test_GovernorCanMint() public {
        vm.prank(admin);
        nova.mint(alice, 1_000e18);
        assertEq(nova.balanceOf(alice), 1_000e18);
    }

    function test_RevertWhen_NonGovernorMints() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NovaPerpToken.NotGovernor.selector, alice));
        nova.mint(alice, 1_000e18);
    }

    function test_RevertWhen_MintExceedsCap() public {
        uint256 cap = nova.MAX_SUPPLY();
        uint256 supply = nova.totalSupply();
        uint256 remaining = cap - supply;
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(NovaPerpToken.CapExceeded.selector, supply + remaining + 1, cap)
        );
        nova.mint(alice, remaining + 1);
    }

    function test_CanMintExactlyToCap() public {
        uint256 remaining = nova.MAX_SUPPLY() - nova.totalSupply();
        vm.prank(admin);
        nova.mint(alice, remaining);
        assertEq(nova.totalSupply(), nova.MAX_SUPPLY());
    }

    function test_BurnReducesSupply() public {
        vm.prank(admin);
        nova.burn(1_000e18);
        assertEq(nova.totalSupply(), 10_000_000e18 - 1_000e18);
    }

    function test_TransferWorks() public {
        vm.prank(admin);
        nova.transfer(alice, 500e18);
        assertEq(nova.balanceOf(alice), 500e18);
    }

    function test_RevertWhen_ConstructedAboveCap() public {
        uint256 cap = nova.MAX_SUPPLY();
        vm.expectRevert(
            abi.encodeWithSelector(NovaPerpToken.CapExceeded.selector, cap + 1, cap)
        );
        new NovaPerpToken(address(roles), admin, cap + 1);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("NOVA: zero roles");
        new NovaPerpToken(address(0), admin, 0);
    }

    function test_RevertWhen_ConstructedWithZeroReceiver() public {
        vm.expectRevert("NOVA: zero receiver");
        new NovaPerpToken(address(roles), address(0), 0);
    }

    function test_PermitDomainSeparatorExists() public view {
        assertTrue(nova.DOMAIN_SEPARATOR() != bytes32(0));
    }

    function testFuzz_MintWithinCap(uint256 amount) public {
        uint256 remaining = nova.MAX_SUPPLY() - nova.totalSupply();
        amount = bound(amount, 1, remaining);
        vm.prank(admin);
        nova.mint(bob, amount);
        assertEq(nova.balanceOf(bob), amount);
    }
}
