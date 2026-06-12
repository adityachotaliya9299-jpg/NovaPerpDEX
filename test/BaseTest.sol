// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {Test} from "forge-std/Test.sol";
import {RoleManager} from "../src/core/RoleManager.sol";
import {Vault} from "../src/core/Vault.sol";
import {PriceFeed} from "../src/core/PriceFeed.sol";
import {NovaPerpToken} from "../src/core/NovaPerpToken.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @title BaseTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Shared fixture deploying the full Phase 1 stack with sensible roles.
/// @dev Inherited by every unit/fuzz suite so setup stays DRY and consistent.
contract BaseTest is Test {
    RoleManager internal roles;
    Vault internal vault;
    PriceFeed internal priceFeed;
    NovaPerpToken internal nova;
    MockERC20 internal usdc;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal keeper = makeAddr("keeper");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant ETH_USD = keccak256("ETH-USD");

    uint256 internal constant STALENESS = 1 hours;

    function setUp() public virtual {
        vm.startPrank(admin);
        roles = new RoleManager(admin);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new Vault(address(usdc), address(roles));
        priceFeed = new PriceFeed(address(roles), STALENESS);
        nova = new NovaPerpToken(address(roles), admin, 10_000_000e18);

        roles.grantRole(roles.OPERATOR_ROLE(), operator);
        roles.grantRole(roles.PRICE_KEEPER_ROLE(), keeper);
        vm.stopPrank();
    }

    /// @notice Mints `amount` USDC to `to` and approves the vault.
    function _fund(address to, uint256 amount) internal {
        usdc.mint(to, amount);
        vm.prank(to);
        usdc.approve(address(vault), amount);
    }
}
