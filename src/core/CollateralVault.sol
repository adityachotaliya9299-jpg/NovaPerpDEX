// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Math} from "../libraries/Math.sol";
import {IBadDebtHandler} from "../interfaces/IBadDebtHandler.sol";
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

    /// @notice Insurance fund address (its locked vault balance backs shortfalls).
    address public insuranceFund;

    /// @notice Records socialized bad debt when the insurance fund is exhausted.
    IBadDebtHandler public badDebtHandler;

    /// @notice Share of the liquidation fee paid to the keeper, in basis points.
    uint256 public keeperRewardBps;

    /// @notice Hard cap on the keeper reward share (50%).
    uint256 public constant MAX_KEEPER_REWARD_BPS = 5_000;

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
    event InsuranceFundSet(address insuranceFund);
    event BadDebtHandlerSet(address badDebtHandler);
    event KeeperRewardBpsSet(uint256 bps);
    event Liquidated(
        bytes32 indexed key,
        address indexed account,
        address indexed keeper,
        uint256 lossToPool,
        uint256 keeperReward,
        uint256 insuranceShare,
        uint256 badDebt
    );

    error NotOperator(address caller);
    error NotGovernor(address caller);
    error ZeroAmount();
    error PoolNotSet();
    error FeeDistributorNotSet();
    error InsuranceFundNotSet();
    error BadDebtHandlerNotSet();
    error KeeperRewardTooHigh(uint256 bps);
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

    function setInsuranceFund(address fund) external onlyGovernor {
        require(fund != address(0), "CV: zero insurance");
        insuranceFund = fund;
        emit InsuranceFundSet(fund);
    }

    function setBadDebtHandler(address handler) external onlyGovernor {
        require(handler != address(0), "CV: zero baddebt");
        badDebtHandler = IBadDebtHandler(handler);
        emit BadDebtHandlerSet(handler);
    }

    function setKeeperRewardBps(uint256 bps) external onlyGovernor {
        if (bps > MAX_KEEPER_REWARD_BPS) revert KeeperRewardTooHigh(bps);
        keeperRewardBps = bps;
        emit KeeperRewardBpsSet(bps);
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

    /// @notice Settles a liquidation: the trader forfeits collateral to cover the loss
    ///         and the liquidation fee, the keeper is rewarded, and any shortfall is
    ///         drawn from the insurance fund or recorded as socialized bad debt.
    /// @param account The position owner being liquidated.
    /// @param market The market.
    /// @param key The position key.
    /// @param collateral The full collateral reserved for the position.
    /// @param pnl Signed realized PnL at the liquidation mark (expected negative).
    /// @param liquidationFee The liquidation fee (WAD USD) to skim from surplus collateral.
    /// @param keeper The address rewarded for triggering the liquidation.
    function liquidate(
        address account,
        bytes32 market,
        bytes32 key,
        uint256 collateral,
        int256 pnl,
        uint256 liquidationFee,
        address keeper
    ) external onlyOperator {
        if (collateral == 0) revert ZeroAmount();
        if (liquidityPool == address(0)) revert PoolNotSet();
        if (insuranceFund == address(0)) revert InsuranceFundNotSet();
        if (address(badDebtHandler) == address(0)) revert BadDebtHandlerNotSet();

        _clearReservation(account, market, key, collateral);

        uint256 absLoss = pnl < 0 ? uint256(-pnl) : 0;

        // 1. Loss to the pool, capped at the collateral.
        uint256 lossToPool = Math.min(absLoss, collateral);
        if (lossToPool > 0) {
            vault.transferLocked(account, liquidityPool, lossToPool);
            vault.lock(liquidityPool, lossToPool);
        }

        // 2. Fee (keeper + insurance) from surplus, remainder back to the trader.
        (uint256 keeperReward, uint256 insuranceShare) =
            _chargeLiquidationFee(account, collateral - lossToPool, liquidationFee, keeper);

        // 3. Shortfall: insurance tops up the pool, remainder is socialized bad debt.
        uint256 badDebt;
        if (absLoss > collateral) {
            badDebt = _coverShortfall(market, absLoss - collateral);
        }

        emit Liquidated(key, account, keeper, lossToPool, keeperReward, insuranceShare, badDebt);
    }

    /// @dev Clears a position's reservation from the ledger (with bounds check).
    function _clearReservation(address account, bytes32 market, bytes32 key, uint256 collateral)
        private
    {
        uint256 reserved = reservedCollateral[key];
        if (collateral > reserved) revert InsufficientReserved(key, collateral, reserved);
        reservedCollateral[key] = reserved - collateral;
        marketReserved[account][market] -= collateral;
        if (marginMode[account][market] == DataTypes.MarginMode.CROSS) {
            crossReserved[account] -= collateral;
        }
    }

    /// @dev Skims the liquidation fee from `surplus`, splitting keeper/insurance, and
    ///      returns any remaining collateral to the trader.
    function _chargeLiquidationFee(
        address account,
        uint256 surplus,
        uint256 liquidationFee,
        address keeper
    ) private returns (uint256 keeperReward, uint256 insuranceShare) {
        uint256 feeCharged = Math.min(liquidationFee, surplus);
        if (feeCharged > 0) {
            keeperReward = feeCharged.bps(keeperRewardBps);
            insuranceShare = feeCharged - keeperReward;
            if (keeperReward > 0) {
                vault.transferLocked(account, keeper, keeperReward);
            }
            if (insuranceShare > 0) {
                vault.transferLocked(account, insuranceFund, insuranceShare);
                vault.lock(insuranceFund, insuranceShare);
            }
        }
        uint256 remaining = surplus - feeCharged;
        if (remaining > 0) {
            vault.unlock(account, remaining);
        }
    }

    /// @dev Covers a pool shortfall from insurance, recording any uncovered remainder
    ///      as socialized bad debt. Returns the recorded bad debt.
    function _coverShortfall(bytes32 market, uint256 shortfall)
        private
        returns (uint256 badDebt)
    {
        uint256 insuranceAvailable = vault.lockedOf(insuranceFund);
        uint256 insuranceCover = Math.min(shortfall, insuranceAvailable);
        if (insuranceCover > 0) {
            vault.transferLocked(insuranceFund, liquidityPool, insuranceCover);
            vault.lock(liquidityPool, insuranceCover);
        }
        badDebt = shortfall - insuranceCover;
        if (badDebt > 0) {
            badDebtHandler.recordBadDebt(market, badDebt);
        }
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