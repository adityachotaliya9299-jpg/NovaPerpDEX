// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RoleManager} from "./RoleManager.sol";
import {Vault} from "./Vault.sol";

/// @title InsuranceFund
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Holds a reserve of locked collateral used to cover liquidation shortfalls
///         before any bad debt is socialized to liquidity providers.
/// @dev The fund's balance is simply its *locked* balance inside the {Vault}; the
///      CollateralVault moves it to the pool during a shortfall via `transferLocked`.
///      This contract handles seeding (deposit + lock) and governed withdrawal of
///      excess reserves. It needs OPERATOR_ROLE to lock/unlock its own balance.
contract InsuranceFund {
    using SafeERC20 for IERC20;

    RoleManager public immutable roles;
    Vault public immutable vault;
    IERC20 public immutable collateralToken;

    event Seeded(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    error NotGovernor(address caller);
    error ZeroAmount();

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager, address vault_, address collateralToken_) {
        require(roleManager != address(0), "IF: zero roles");
        require(vault_ != address(0), "IF: zero vault");
        require(collateralToken_ != address(0), "IF: zero token");
        roles = RoleManager(roleManager);
        vault = Vault(vault_);
        collateralToken = IERC20(collateralToken_);
    }

    /// @notice Seeds the fund: pulls `amount` from the caller and locks it in the vault.
    /// @dev The caller must approve this contract for `amount` of the collateral token.
    function seed(uint256 amount) external onlyGovernor {
        if (amount == 0) revert ZeroAmount();
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateralToken.forceApprove(address(vault), amount);
        vault.deposit(amount); // credits this contract's free balance
        vault.lock(address(this), amount); // free -> locked (requires OPERATOR_ROLE)
        emit Seeded(msg.sender, amount);
    }

    /// @notice Withdraws `amount` of reserve to `to`. Governor-only.
    function withdraw(uint256 amount, address to) external onlyGovernor {
        if (amount == 0) revert ZeroAmount();
        require(to != address(0), "IF: zero to");
        vault.unlock(address(this), amount); // locked -> free
        vault.withdraw(amount); // sends tokens to this contract
        collateralToken.safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    /// @notice The fund's currently locked reserve (WAD USD).
    function balance() external view returns (uint256) {
        return vault.lockedOf(address(this));
    }
}