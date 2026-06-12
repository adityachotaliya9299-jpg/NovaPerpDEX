// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../libraries/Math.sol";
import {RoleManager} from "./RoleManager.sol";
import {Vault} from "./Vault.sol";
import {LPVault} from "../core/LPVault.sol";

/// @title FeeDistributor
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Tracks and routes the position fees charged by the margin engine.
/// @dev Fees physically land as this contract's *free* balance inside the {Vault}
///      (moved there by the CollateralVault during open/settle). `accrue` records the
///      bookkeeping; `collect` pulls the tokens out and forwards them to the treasury.
///      Splitting fees to LP and stakers is wired in later phases — the accounting
///      hooks live here so those phases plug in without changing the trading path.
contract FeeDistributor {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Hard cap on the configurable position fee (1% of notional).
    uint256 public constant MAX_POSITION_FEE_BPS = 100;

    RoleManager public immutable roles;
    Vault public immutable vault;
    IERC20 public immutable collateralToken;

    /// @notice Position fee charged on size, in basis points (both open and close).
    uint256 public positionFeeBps;

    /// @notice Treasury receiving collected fees.
    address public treasury;

    /// @notice Cumulative fees accrued across all markets (WAD USD).
    uint256 public totalFees;

    /// @notice Cumulative fees accrued per market (WAD USD).
    mapping(bytes32 => uint256) public feesByMarket;

    event FeeAccrued(bytes32 indexed market, uint256 amount);
    event FeesCollected(address indexed to, uint256 amount);
    event PositionFeeSet(uint256 bps);
    event TreasurySet(address treasury);
    event FeesSplit(address indexed lpVault, uint256 lpShare, uint256 treasuryShare);

    error NotOperator(address caller);
    error NotGovernor(address caller);
    error FeeTooHigh(uint256 bps);
    error ZeroTreasury();

    modifier onlyOperator() {
        if (!roles.isOperator(msg.sender)) revert NotOperator(msg.sender);
        _;
    }

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    /// @param roleManager Shared RoleManager.
    /// @param vault_ The collateral Vault holding fee balances.
    /// @param collateralToken_ The collateral token (must match the vault's token).
    /// @param treasury_ Initial treasury address.
    /// @param positionFeeBps_ Initial position fee in basis points.
    constructor(
        address roleManager,
        address vault_,
        address collateralToken_,
        address treasury_,
        uint256 positionFeeBps_
    ) {
        require(roleManager != address(0), "FD: zero roles");
        require(vault_ != address(0), "FD: zero vault");
        require(collateralToken_ != address(0), "FD: zero token");
        if (treasury_ == address(0)) revert ZeroTreasury();
        if (positionFeeBps_ > MAX_POSITION_FEE_BPS) revert FeeTooHigh(positionFeeBps_);
        roles = RoleManager(roleManager);
        vault = Vault(vault_);
        collateralToken = IERC20(collateralToken_);
        treasury = treasury_;
        positionFeeBps = positionFeeBps_;
    }

    /// @notice Computes the position fee for a given notional size.
    function feeOnSize(uint256 size) external view returns (uint256) {
        return size.bps(positionFeeBps);
    }

    /// @notice Records that `amount` of fees was charged on `market`. Operator-only.
    /// @dev The tokens themselves are already in this contract's vault balance.
    function accrue(bytes32 market, uint256 amount) external onlyOperator {
        if (amount == 0) return;
        totalFees += amount;
        feesByMarket[market] += amount;
        emit FeeAccrued(market, amount);
    }

    /// @notice Pulls `amount` of accrued fees out of the vault to the treasury. Governor-only.
    function collect(uint256 amount) external onlyGovernor {
        vault.withdraw(amount); // vault sends tokens to this contract
        collateralToken.safeTransfer(treasury, amount);
        emit FeesCollected(treasury, amount);
    }


    /// @notice Pulls `amount` out of the vault and splits it between `lpVault` and the
    ///         treasury by `lpShareBps`. Governor-only (intended caller: a
    ///         {SettlementEngine} granted GOVERNOR_ROLE for epoch settlement).
    /// @dev The LP share is routed via `LPVault.donate`, which deposits it into the
    ///      protocol vault on the LPVault's behalf without minting shares — this is
    ///      what actually raises `totalAssets()` and therefore share price for all LPs.
    ///      A bare ERC20 transfer to the LPVault's address would NOT do this (the
    ///      tokens would sit untracked), so `donate` is the only correct path.
    function collectAndSplit(uint256 amount, address lpVault, uint256 lpShareBps)
        external
        onlyGovernor
        returns (uint256 lpShare, uint256 treasuryShare)
    {
        if (lpShareBps > Math.BPS_DENOMINATOR) revert FeeTooHigh(lpShareBps);
        lpShare = amount.bps(lpShareBps);
        treasuryShare = amount - lpShare;

        vault.withdraw(amount); // entire amount lands here as raw tokens

        // If no LPs exist yet, donate() would revert; route the LP share to treasury
        // instead so epoch settlement never strands funds or blocks on an empty pool.
        if (lpShare > 0 && LPVault(lpVault).totalSupply() == 0) {
            treasuryShare += lpShare;
            lpShare = 0;
        }

        if (lpShare > 0) {
            collateralToken.forceApprove(lpVault, lpShare);
            LPVault(lpVault).donate(lpShare);
        }
        if (treasuryShare > 0) {
            collateralToken.safeTransfer(treasury, treasuryShare);
        }
        emit FeesCollected(treasury, treasuryShare);
        emit FeesSplit(lpVault, lpShare, treasuryShare);
    }

    /// @notice Sets the position fee (bounded by MAX_POSITION_FEE_BPS). Governor-only.
    function setPositionFeeBps(uint256 newBps) external onlyGovernor {
        if (newBps > MAX_POSITION_FEE_BPS) revert FeeTooHigh(newBps);
        positionFeeBps = newBps;
        emit PositionFeeSet(newBps);
    }

    /// @notice Updates the treasury address. Governor-only.
    function setTreasury(address newTreasury) external onlyGovernor {
        if (newTreasury == address(0)) revert ZeroTreasury();
        treasury = newTreasury;
        emit TreasurySet(newTreasury);
    }

    /// @notice Fee balance currently sitting in the vault for this contract.
    function pendingInVault() external view returns (uint256) {
        return vault.balanceOf(address(this));
    }
}
