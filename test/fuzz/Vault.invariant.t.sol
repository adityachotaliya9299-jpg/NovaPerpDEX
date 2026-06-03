// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {Test} from "forge-std/Test.sol";
import {RoleManager} from "../../src/core/RoleManager.sol";
import {Vault} from "../../src/core/Vault.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Handler that drives randomized vault operations for invariant testing.
contract VaultHandler is Test {
    Vault public vault;
    MockERC20 public usdc;
    address public operator;
    address[] public actors;

    constructor(Vault _vault, MockERC20 _usdc, address _operator) {
        vault = _vault;
        usdc = _usdc;
        operator = _operator;
        actors.push(makeAddr("a1"));
        actors.push(makeAddr("a2"));
        actors.push(makeAddr("a3"));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 1, 1_000_000e6);
        usdc.mint(actor, amount);
        vm.startPrank(actor);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 free = vault.balanceOf(actor);
        if (free == 0) return;
        amount = bound(amount, 1, free);
        vm.prank(actor);
        vault.withdraw(amount);
    }

    function lock(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 free = vault.balanceOf(actor);
        if (free == 0) return;
        amount = bound(amount, 1, free);
        vm.prank(operator);
        vault.lock(actor, amount);
    }

    function unlock(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 locked = vault.lockedOf(actor);
        if (locked == 0) return;
        amount = bound(amount, 1, locked);
        vm.prank(operator);
        vault.unlock(actor, amount);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }
}

/// @title VaultInvariantTest
/// @notice Invariant: the vault's token balance always equals totalCollateral, and
///         totalCollateral always equals the sum of every actor's free + locked.
contract VaultInvariantTest is Test {
    RoleManager internal roles;
    Vault internal vault;
    MockERC20 internal usdc;
    VaultHandler internal handler;
    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");

    function setUp() public {
        vm.startPrank(admin);
        roles = new RoleManager(admin);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new Vault(address(usdc), address(roles));
        roles.grantRole(roles.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        handler = new VaultHandler(vault, usdc, operator);
        targetContract(address(handler));
    }

    /// @notice The ERC20 held by the vault must equal its accounted totalCollateral.
    function invariant_TokenBalanceMatchesTotal() public view {
        assertEq(usdc.balanceOf(address(vault)), vault.totalCollateral());
    }

    /// @notice Sum of all actors' (free + locked) equals totalCollateral.
    function invariant_SumOfBalancesMatchesTotal() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; i++) {
            sum += vault.totalOf(handler.actorAt(i));
        }
        assertEq(sum, vault.totalCollateral());
    }
}
