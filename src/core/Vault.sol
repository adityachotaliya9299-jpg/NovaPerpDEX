// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IVault} from "../interfaces/IVault.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title Vault
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Custodies a single ERC20 collateral token (e.g. USDC) on behalf of traders.
/// @dev The vault is intentionally "dumb" — it tracks free balances and lets
///      OPERATOR_ROLE modules (the margin engine in Phase 2) lock, unlock and
///      transfer collateral between accounts. It never decides solvency itself.
///      All external token movements use SafeERC20 and are reentrancy-guarded.
contract Vault is IVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The collateral token custodied by this vault.
    IERC20 public immutable collateralToken;

    /// @notice Shared role registry.
    RoleManager public immutable roles;

    /// @notice Free (withdrawable) collateral per account.
    mapping(address => uint256) private _free;

    /// @notice Collateral locked into open positions per account.
    mapping(address => uint256) private _locked;

    /// @notice Total collateral (free + locked) held by the vault.
    uint256 public totalCollateral;

    error ZeroAmount();
    error InsufficientFree(address account, uint256 requested, uint256 available);
    error InsufficientLocked(address account, uint256 requested, uint256 available);
    error NotOperator(address caller);

    /// @notice Emitted when collateral is locked against a position.
    event CollateralLocked(address indexed account, uint256 amount);
    /// @notice Emitted when collateral is unlocked back to free balance.
    event CollateralUnlocked(address indexed account, uint256 amount);

    modifier onlyOperator() {
        if (!roles.isOperator(msg.sender)) revert NotOperator(msg.sender);
        _;
    }

    /// @param collateralToken_ The ERC20 collateral token.
    /// @param roleManager Address of the shared RoleManager.
    constructor(address collateralToken_, address roleManager) {
        require(collateralToken_ != address(0), "Vault: zero token");
        require(roleManager != address(0), "Vault: zero roles");
        collateralToken = IERC20(collateralToken_);
        roles = RoleManager(roleManager);
    }

    /// @inheritdoc IVault
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        _free[msg.sender] += amount;
        totalCollateral += amount;
        emit Deposited(msg.sender, address(collateralToken), amount);
    }

    /// @inheritdoc IVault
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 free = _free[msg.sender];
        if (amount > free) revert InsufficientFree(msg.sender, amount, free);
        _free[msg.sender] = free - amount;
        totalCollateral -= amount;
        collateralToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, address(collateralToken), amount);
    }

    /// @notice Moves `amount` from an account's free balance into locked. Operator-only.
    /// @dev Used by the margin engine when a position is opened or increased.
    function lock(address account, uint256 amount) external onlyOperator {
        if (amount == 0) revert ZeroAmount();
        uint256 free = _free[account];
        if (amount > free) revert InsufficientFree(account, amount, free);
        _free[account] = free - amount;
        _locked[account] += amount;
        emit CollateralLocked(account, amount);
    }

    /// @notice Moves `amount` from an account's locked balance back to free. Operator-only.
    function unlock(address account, uint256 amount) external onlyOperator {
        if (amount == 0) revert ZeroAmount();
        uint256 locked = _locked[account];
        if (amount > locked) revert InsufficientLocked(account, amount, locked);
        _locked[account] = locked - amount;
        _free[account] += amount;
        emit CollateralUnlocked(account, amount);
    }

    /// @notice Transfers locked collateral from one account to another's free balance.
    /// @dev Used to realize PnL/fees: e.g. moving a loser's locked collateral to the
    ///      LP pool or insurance fund. Operator-only.
    function transferLocked(address from, address to, uint256 amount) external onlyOperator {
        if (amount == 0) revert ZeroAmount();
        uint256 locked = _locked[from];
        if (amount > locked) revert InsufficientLocked(from, amount, locked);
        _locked[from] = locked - amount;
        _free[to] += amount;
        emit CollateralTransferred(from, to, amount);
    }

    /// @inheritdoc IVault
    function balanceOf(address account) external view returns (uint256) {
        return _free[account];
    }

    /// @notice Returns the locked collateral of `account`.
    function lockedOf(address account) external view returns (uint256) {
        return _locked[account];
    }

    /// @notice Returns total (free + locked) collateral of `account`.
    function totalOf(address account) external view returns (uint256) {
        return _free[account] + _locked[account];
    }
}
