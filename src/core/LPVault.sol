// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vault} from "./Vault.sol";

/// @title LPVault
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice ERC4626-style share vault over the protocol's counterparty liquidity pool.
/// @dev This contract's address IS `liquidityPool` in {CollateralVault} — the same
///      address that has been settling trader PnL since Phase 2 via
///      `vault.transferLocked` / `lock` / `unlock`. No settlement logic changes: those
///      calls already move collateral into and out of `vault.totalOf(address(this))`,
///      so {totalAssets} automatically reflects every win/loss the pool has absorbed.
///      LPVault adds only the deposit/withdraw/share-accounting layer on top.
///
///      Shares are WAD-scaled 1e18 = 1 share at a 1:1 price, matching the 18-decimal
///      collateral. The first deposit mints a small amount of "dead shares" to the zero
///      address, mitigating the classic empty-vault share-price inflation attack.
contract LPVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Minimum first-deposit size, also the size of the permanently-locked
    ///         dead shares minted on initialization. Prevents the empty-vault
    ///         donate-then-mint-1-wei share-price manipulation.
    uint256 public constant MIN_FIRST_DEPOSIT = 1e6; // 1e-12 of one WAD unit

    /// @notice The underlying collateral token (must match `vault.collateralToken`).
    IERC20 public immutable asset;

    /// @notice The protocol vault this contract deposits into / withdraws from.
    Vault public immutable vault;

    /// @notice Total LP shares outstanding (including dead shares).
    uint256 public totalSupply;

    /// @notice LP share balances.
    mapping(address => uint256) public balanceOf;

    /// @notice ERC20-style allowances for share transfers (used by {RewardDistributor}
    ///         staking and any future share-aware integrations).
    mapping(address => mapping(address => uint256)) public allowance;

    event Deposit(address indexed lp, uint256 assets, uint256 shares);
    event Withdraw(address indexed lp, uint256 assets, uint256 shares);
    event Donate(address indexed donor, uint256 assets);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    error ZeroAmount();
    error BelowMinFirstDeposit(uint256 amount, uint256 min);
    error InsufficientShares(address lp, uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error InsufficientAllowance(address owner, address spender, uint256 requested, uint256 available);

    constructor(address asset_, address vault_) {
        require(asset_ != address(0), "LPV: zero asset");
        require(vault_ != address(0), "LPV: zero vault");
        asset = IERC20(asset_);
        vault = Vault(vault_);
    }

    /// @notice Total LP-owned assets: free + locked balance of this contract in the
    ///         protocol vault. Locked collateral is collateral currently reserved
    ///         against trader losses — still LP equity, just encumbered.
    function totalAssets() public view returns (uint256) {
        return vault.totalOf(address(this));
    }

    /// @notice Assets currently withdrawable without waiting on trader settlement.
    function availableLiquidity() public view returns (uint256) {
        return vault.balanceOf(address(this));
    }

    /// @notice Shares that would be minted for depositing `assets`, at the current price.
    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return assets; // 1:1 on first real deposit (before dead shares)
        return (assets * supply) / totalAssets();
    }

    /// @notice Assets that would be returned for redeeming `shares`, at the current price.
    function previewRedeem(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return 0;
        return (shares * totalAssets()) / supply;
    }

    /// @notice Deposits `assets` of collateral, minting LP shares at the current price.
    /// @dev On the very first deposit, mints {MIN_FIRST_DEPOSIT} dead shares to address(1)
    ///      in addition to the depositor's shares, permanently raising the cost of the
    ///      inflation attack without giving up any of the depositor's own value.
    function deposit(uint256 assets) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        uint256 supply = totalSupply;
        if (supply == 0) {
            if (assets < MIN_FIRST_DEPOSIT) revert BelowMinFirstDeposit(assets, MIN_FIRST_DEPOSIT);
            shares = assets - MIN_FIRST_DEPOSIT;
            _mint(address(1), MIN_FIRST_DEPOSIT); // dead shares, permanently locked
        } else {
            shares = (assets * supply) / totalAssets();
        }
        if (shares == 0) revert ZeroAmount();

        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(address(vault), assets);
        vault.deposit(assets);

        _mint(msg.sender, shares);
        emit Deposit(msg.sender, assets, shares);
    }

    /// @notice Deposits `assets` into the protocol vault on this contract's behalf
    ///         WITHOUT minting any shares, raising {totalAssets} (and therefore
    ///         {sharePrice}) for all existing LPs. Used by {FeeDistributor} to route
    ///         the LP share of protocol fees directly into LP yield.
    /// @dev Permissionless by design: anyone donating value to LPs needs no gate. The
    ///      caller must have approved this contract for `assets` beforehand. Reverts
    ///      with {ZeroAmount} if called before any real deposit exists (no LPs to
    ///      benefit, and dividing by totalSupply==0 elsewhere would be meaningless).
    function donate(uint256 assets) external nonReentrant {
        if (assets == 0) revert ZeroAmount();
        if (totalSupply == 0) revert ZeroAmount();
        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(address(vault), assets);
        vault.deposit(assets);
        emit Donate(msg.sender, assets);
    }

    /// @notice Burns `shares` and returns the corresponding assets to the caller.
    /// @dev Reverts with {InsufficientLiquidity} if the pool's free balance can't cover
    ///      the redemption — i.e. too much of the pool is currently reserved against
    ///      open trader losses. This is the real liquidity constraint, not an artifact.
    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        uint256 bal = balanceOf[msg.sender];
        if (shares > bal) revert InsufficientShares(msg.sender, shares, bal);

        assets = (shares * totalAssets()) / totalSupply;
        if (assets == 0) revert ZeroAmount();

        uint256 available = availableLiquidity();
        if (assets > available) revert InsufficientLiquidity(assets, available);

        _burn(msg.sender, shares);
        vault.withdraw(assets);
        asset.safeTransfer(msg.sender, assets);

        emit Withdraw(msg.sender, assets, shares);
    }

    /// @notice Current share price, in WAD (1e18 = 1 share is worth 1 unit of asset).
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return 1e18;
        return OZMath.mulDiv(totalAssets(), 1e18, supply);
    }

    // --------------------------------------------------------------------- //
    //                    Minimal ERC20-style share transfers                //
    // --------------------------------------------------------------------- //
    // LP shares aren't a full ERC20 (no name/symbol/decimals), but expose the
    // transfer/approve/transferFrom surface needed for {RewardDistributor} staking
    // and any future share-aware integrations.

    /// @notice Transfers `amount` of the caller's shares to `to`.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Approves `spender` to transfer up to `amount` of the caller's shares.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers `amount` of `from`'s shares to `to`, spending `from`'s
    ///         allowance for the caller.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (amount > allowed) revert InsufficientAllowance(from, msg.sender, amount, allowed);
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert InsufficientShares(from, amount, bal);
        balanceOf[from] = bal - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) private {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) private {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}