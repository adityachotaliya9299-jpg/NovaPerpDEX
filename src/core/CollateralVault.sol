// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Math} from "../libraries/Math.sol";
import {RoleManager} from "./RoleManager.sol";
import {Vault} from "./Vault.sol";
import {FeeDistributor} from "./FeeDistributor.sol";

/// @title CollateralVault
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice The single owner of all collateral movement for the margin engine.
/// @dev MarginManager computes position state and PnL but delegates *every* token
///      movement to this contract, so the reservation ledger here can never diverge
///      from the locked balances in the underlying {Vault}. This is the one place
///      that touches the counterparty pool, making the value-conservation invariant
///      auditable in isolation.
///
///      Settlement model (conservation-preserving, no value minted):
///        - profit: paid from the liquidity pool's locked balance to the trader.
///        - loss:   moved from the trader to the pool and re-locked there.
///        - fee:    moved from the trader's released collateral to the FeeDistributor.
contract CollateralVault {
    using Math for uint256;

    RoleManager public immutable roles;
    Vault public immutable vault;

    /// @notice The counterparty pool backing trader PnL (becomes the LPVault in Phase 6).
    address public liquidityPool;

    /// @notice The fee sink.
    FeeDistributor public feeDistributor;

    /// @notice positionKey => collateral reserved (locked) for that position (WAD USD).
    mapping(bytes32 => uint256) public reservedCollateral;

    /// @notice account => market => total collateral reserved across that market.
    mapping(address => mapping(bytes32 => uint256)) public marketReserved;

    /// @notice account => total cross-margin collateral reserved.
    mapping(address => uint256) public crossReserved;

    /// @notice account => market => margin mode (defaults to ISOLATED).
    mapping(address => mapping(bytes32 => DataTypes.MarginMode)) public marginMode;

    event MarginModeSet(address indexed account, bytes32 indexed market, DataTypes.MarginMode mode);
    event Reserved(bytes32 indexed key, address indexed account, uint256 amount);
    event Released(bytes32 indexed key, address indexed account, uint256 amount);
    event Settled(bytes32 indexed key, address indexed account, int256 pnl, uint256 fee);
    event LiquidityPoolSet(address pool);
    event FeeDistributorSet(address feeDistributor);

    error NotOperator(address caller);
    error NotGovernor(address caller);
    error ZeroAmount();
    error PoolNotSet();
    error FeeDistributorNotSet();
    error ModeChangeWhileOpen(address account, bytes32 market);
    error InsufficientReserved(bytes32 key, uint256 requested, uint256 available);

    modifier onlyOperator() {
        if (!roles.isOperator(msg.sender)) revert NotOperator(msg.sender);
        _;
    }

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager, address vault_) {
        require(roleManager != address(0), "CV: zero roles");
        require(vault_ != address(0), "CV: zero vault");
        roles = RoleManager(roleManager);
        vault = Vault(vault_);
    }

    // --------------------------------------------------------------------- //
    //                               Admin                                   //
    // --------------------------------------------------------------------- //

    function setLiquidityPool(address pool) external onlyGovernor {
        require(pool != address(0), "CV: zero pool");
        liquidityPool = pool;
        emit LiquidityPoolSet(pool);
    }

    function setFeeDistributor(address fd) external onlyGovernor {
        require(fd != address(0), "CV: zero fd");
        feeDistributor = FeeDistributor(fd);
        emit FeeDistributorSet(fd);
    }

    /// @notice Sets the margin mode for an account on a market. Operator-only.
    /// @dev Only permitted while the account is flat on that market.
    function setMarginMode(address account, bytes32 market, DataTypes.MarginMode mode)
        external
        onlyOperator
    {
        if (marketReserved[account][market] != 0) revert ModeChangeWhileOpen(account, market);
        marginMode[account][market] = mode;
        emit MarginModeSet(account, market, mode);
    }

    // --------------------------------------------------------------------- //
    //                          Collateral movement                         //
    // --------------------------------------------------------------------- //

    /// @notice Reserves `collateral` for a position and routes `fee` to the fee sink.
    /// @dev Locks `collateral + fee` from the trader's free balance, forwards the fee,
    ///      and records the reservation. Operator-only (called by MarginManager).
    function reserve(
        address account,
        bytes32 market,
        bytes32 key,
        uint256 collateral,
        uint256 fee
    ) external onlyOperator {
        if (collateral == 0) revert ZeroAmount();
        if (address(feeDistributor) == address(0)) revert FeeDistributorNotSet();

        vault.lock(account, collateral + fee);
        if (fee > 0) {
            vault.transferLocked(account, address(feeDistributor), fee);
            feeDistributor.accrue(market, fee);
        }

        reservedCollateral[key] += collateral;
        marketReserved[account][market] += collateral;
        if (marginMode[account][market] == DataTypes.MarginMode.CROSS) {
            crossReserved[account] += collateral;
        }
        emit Reserved(key, account, collateral);
    }

    /// @notice Adds `amount` of collateral to an existing reservation. Operator-only.
    function addCollateral(address account, bytes32 market, bytes32 key, uint256 amount)
        external
        onlyOperator
    {
        if (amount == 0) revert ZeroAmount();
        vault.lock(account, amount);
        reservedCollateral[key] += amount;
        marketReserved[account][market] += amount;
        if (marginMode[account][market] == DataTypes.MarginMode.CROSS) {
            crossReserved[account] += amount;
        }
        emit Reserved(key, account, amount);
    }

    /// @notice Removes `amount` of collateral from a reservation back to free. Operator-only.
    function removeCollateral(address account, bytes32 market, bytes32 key, uint256 amount)
        external
        onlyOperator
    {
        if (amount == 0) revert ZeroAmount();
        uint256 reserved = reservedCollateral[key];
        if (amount > reserved) revert InsufficientReserved(key, amount, reserved);

        reservedCollateral[key] = reserved - amount;
        marketReserved[account][market] -= amount;
        if (marginMode[account][market] == DataTypes.MarginMode.CROSS) {
            crossReserved[account] -= amount;
        }
        vault.unlock(account, amount);
        emit Released(key, account, amount);
    }

    /// @notice Settles a (partial) close: realizes PnL against the pool, charges the
    ///         close fee, and releases the remaining collateral to the trader.
    /// @param account The position owner.
    /// @param market The market.
    /// @param key The position key.
    /// @param collateralPortion The collateral being released for the closed size.
    /// @param pnl Signed realized PnL for the closed portion (WAD USD).
    /// @param fee Close fee to charge (WAD USD).
    function settle(
        address account,
        bytes32 market,
        bytes32 key,
        uint256 collateralPortion,
        int256 pnl,
        uint256 fee
    ) external onlyOperator {
        if (collateralPortion == 0) revert ZeroAmount();
        if (liquidityPool == address(0)) revert PoolNotSet();
        if (address(feeDistributor) == address(0)) revert FeeDistributorNotSet();

        uint256 reserved = reservedCollateral[key];
        if (collateralPortion > reserved) {
            revert InsufficientReserved(key, collateralPortion, reserved);
        }

        // Update the ledger up front; token moves below net to exactly collateralPortion.
        reservedCollateral[key] = reserved - collateralPortion;
        marketReserved[account][market] -= collateralPortion;
        if (marginMode[account][market] == DataTypes.MarginMode.CROSS) {
            crossReserved[account] -= collateralPortion;
        }

        uint256 remaining = collateralPortion;

        if (pnl >= 0) {
            // Profit: pool pays the trader (reverts if pool is insolvent — intended).
            uint256 profit = uint256(pnl);
            if (profit > 0) {
                vault.transferLocked(liquidityPool, account, profit);
            }
        } else {
            // Loss: capped at the collateral; move to pool and re-lock it there.
            uint256 loss = Math.min(uint256(-pnl), remaining);
            if (loss > 0) {
                vault.transferLocked(account, liquidityPool, loss); // -> pool.free
                vault.lock(liquidityPool, loss); // pool.free -> pool.locked
                remaining -= loss;
            }
        }

        // Close fee taken from whatever collateral remains.
        uint256 feeToCharge = Math.min(fee, remaining);
        if (feeToCharge > 0) {
            vault.transferLocked(account, address(feeDistributor), feeToCharge);
            feeDistributor.accrue(market, feeToCharge);
            remaining -= feeToCharge;
        }

        // Return the rest to the trader's free balance.
        if (remaining > 0) {
            vault.unlock(account, remaining);
        }

        emit Settled(key, account, pnl, feeToCharge);
    }

    // --------------------------------------------------------------------- //
    //                               Views                                   //
    // --------------------------------------------------------------------- //

    function getMarginMode(address account, bytes32 market)
        external
        view
        returns (DataTypes.MarginMode)
    {
        return marginMode[account][market];
    }
}
