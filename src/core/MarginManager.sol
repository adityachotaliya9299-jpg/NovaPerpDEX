// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Math} from "../libraries/Math.sol";
import {PositionLib} from "../libraries/PositionLib.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {RoleManager} from "./RoleManager.sol";
import {LeverageController} from "./LeverageController.sol";
import {CollateralVault} from "./CollateralVault.sol";
import {FeeDistributor} from "./FeeDistributor.sol";
import {FundingRateEngine} from "./FundingRateEngine.sol";
import {RiskManager} from "./RiskManager.sol";

/// @title MarginManager
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice The trading entry point: opens, increases, decreases and closes leveraged
///         perpetual positions.
/// @dev Owns position state and open-interest accounting, reads marks from the
///      {IPriceFeed}, validates risk via {LeverageController}, prices fees via
///      {FeeDistributor}, and delegates *all* collateral movement to {CollateralVault}.
///      It never moves tokens itself — that separation keeps value conservation
///      provable in the CollateralVault alone.
///
///      Phase 5 wiring (all optional; unset refs preserve earlier behavior exactly):
///        - {FundingRateEngine}: folds funding into entry snapshots, settlement and health.
///        - {RiskManager}: skew limits and skew-scaled dynamic fees on increase.
///        - router allowlist: lets conditional-order contracts act on behalf of users.
contract MarginManager {
    using Math for uint256;
    using PositionLib for DataTypes.Position;

    RoleManager public immutable roles;
    IPriceFeed public immutable priceFeed;
    LeverageController public immutable leverageController;
    CollateralVault public immutable collateralVault;
    FeeDistributor public immutable feeDistributor;

    /// @notice Optional funding engine; when set, funding folds into the trade path.
    FundingRateEngine public fundingEngine;

    /// @notice Optional risk manager; when set, applies skew limits + dynamic fees.
    RiskManager public riskManager;

    /// @notice Addresses permitted to trade on behalf of users (routers, order books).
    mapping(address => bool) public authorizedRouter;

    /// @notice positionKey => position.
    mapping(bytes32 => DataTypes.Position) private _positions;

    /// @notice market => total long open interest (WAD USD notional).
    mapping(bytes32 => uint256) public longOpenInterest;

    /// @notice market => total short open interest (WAD USD notional).
    mapping(bytes32 => uint256) public shortOpenInterest;


    event PositionIncreased(
        bytes32 indexed key,
        address indexed account,
        bytes32 indexed market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 price
    );
    event PositionDecreased(
        bytes32 indexed key,
        address indexed account,
        bytes32 indexed market,
        uint256 sizeDelta,
        int256 realizedPnl,
        uint256 price
    );
    event CollateralAdded(bytes32 indexed key, uint256 amount);
    event CollateralRemoved(bytes32 indexed key, uint256 amount);

    error ZeroSize();
    error NoPosition(bytes32 key);
    error SizeExceedsPosition(uint256 sizeDelta, uint256 size);
    error OpenInterestCap(bytes32 market, uint256 attempted, uint256 cap);
    error CollateralBelowMin();
    error NotLiquidator(address caller);
    error NotLiquidatable(bytes32 key);
    error NotGovernor(address caller);
    error NotRouter(address caller);

    event PositionLiquidated(
        bytes32 indexed key,
        address indexed account,
        bytes32 indexed market,
        address keeper,
        uint256 size,
        int256 pnl,
        uint256 price
    );
    event FundingEngineSet(address engine);
    event RiskManagerSet(address riskManager);
    event RouterSet(address router, bool allowed);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    modifier onlyRouter() {
        if (!authorizedRouter[msg.sender]) revert NotRouter(msg.sender);
        _;
    }

    constructor(
        address roleManager,
        address priceFeed_,
        address leverage_,
        address collateralVault_,
        address feeDistributor_
    ) {
        require(roleManager != address(0), "MM: zero roles");
        require(priceFeed_ != address(0), "MM: zero feed");
        require(leverage_ != address(0), "MM: zero leverage");
        require(collateralVault_ != address(0), "MM: zero cv");
        require(feeDistributor_ != address(0), "MM: zero fd");
        roles = RoleManager(roleManager);
        priceFeed = IPriceFeed(priceFeed_);
        leverageController = LeverageController(leverage_);
        collateralVault = CollateralVault(collateralVault_);
        feeDistributor = FeeDistributor(feeDistributor_);
    }

    // --------------------------------------------------------------------- //
    //                          Phase 5 wiring (admin)                       //
    // --------------------------------------------------------------------- //

    function setFundingEngine(address engine) external onlyGovernor {
        fundingEngine = FundingRateEngine(engine);
        emit FundingEngineSet(engine);
    }

    function setRiskManager(address rm) external onlyGovernor {
        riskManager = RiskManager(rm);
        emit RiskManagerSet(rm);
    }

    function setRouter(address router, bool allowed) external onlyGovernor {
        require(router != address(0), "MM: zero router");
        authorizedRouter[router] = allowed;
        emit RouterSet(router, allowed);
    }

    /// @notice Deterministic key for a position.
    function positionKey(address account, bytes32 market, DataTypes.Side side)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(account, market, uint8(side)));
    }

    /// @notice Sets the caller's margin mode for a market (only while flat).
    function setMarginMode(bytes32 market, DataTypes.MarginMode mode) external {
        collateralVault.setMarginMode(msg.sender, market, mode);
    }

    /// @notice Opens or increases a position.
    /// @param market The market identifier.
    /// @param side LONG or SHORT.
    /// @param sizeDelta Notional size to add (WAD USD).
    /// @param collateralDelta Collateral to add (WAD USD).
    function increasePosition(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta
    ) external {
        _increase(msg.sender, market, side, sizeDelta, collateralDelta);
    }

    /// @notice Router-gated open/increase on behalf of `account` (order books, routers).
    function increasePositionFor(
        address account,
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta
    ) external onlyRouter {
        _increase(account, market, side, sizeDelta, collateralDelta);
    }

    /// @dev Shared open/increase logic. Funding snapshot and risk checks apply only
    ///      when their engines are wired (otherwise behavior matches earlier phases).
    function _increase(
        address account,
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta
    ) private {
        if (sizeDelta == 0) revert ZeroSize();
        bytes32 key = positionKey(account, market, side);
        DataTypes.Position storage p = _positions[key];

        uint256 price = priceFeed.getPrice(market);
        uint256 oldSize = p.size;

        // Aggregate-leverage and (optional) skew checks.
        leverageController.validatePosition(market, oldSize + sizeDelta, p.collateral + collateralDelta);
        if (address(riskManager) != address(0)) {
            riskManager.validateSkew(
                market, side, sizeDelta, longOpenInterest[market], shortOpenInterest[market]
            );
        }
        _checkAndUpdateOpenInterest(market, side, sizeDelta, true);

        // Reserve collateral and charge the (possibly dynamic) open fee.
        collateralVault.reserve(account, market, key, collateralDelta, _openFee(market, side, sizeDelta));

        // Entry-price + funding-index snapshots.
        if (oldSize == 0) {
            p.owner = account;
            p.market = market;
            p.side = side;
            p.entryPrice = price;
            p.status = DataTypes.PositionStatus.OPEN;
            if (address(fundingEngine) != address(0)) {
                p.entryFundingIndex = fundingEngine.pendingIndex(market);
            }
        } else {
            p.entryPrice = PositionLib.blendedEntryPrice(oldSize, p.entryPrice, sizeDelta, price);
            if (address(fundingEngine) != address(0)) {
                p.entryFundingIndex = PositionLib.blendedFundingIndex(
                    oldSize, p.entryFundingIndex, sizeDelta, fundingEngine.pendingIndex(market)
                );
            }
        }
        p.size = oldSize + sizeDelta;
        p.collateral += collateralDelta;
        p.lastIncreasedAt = uint64(block.timestamp);

        emit PositionIncreased(key, account, market, side, sizeDelta, collateralDelta, price);
    }

    /// @dev The open fee in WAD USD: dynamic (risk-managed) when wired, else flat.
    function _openFee(bytes32 market, DataTypes.Side side, uint256 sizeDelta)
        private
        view
        returns (uint256)
    {
        if (address(riskManager) != address(0)) {
            uint256 bps = riskManager.feeBps(
                market, side, sizeDelta, longOpenInterest[market], shortOpenInterest[market]
            );
            return sizeDelta.bps(bps);
        }
        return feeDistributor.feeOnSize(sizeDelta);
    }

    /// @notice Decreases (partially or fully closes) a position, realizing PnL.
    /// @param market The market identifier.
    /// @param side LONG or SHORT.
    /// @param sizeDelta Notional size to close (WAD USD). Equal to size for a full close.
    function decreasePosition(bytes32 market, DataTypes.Side side, uint256 sizeDelta)
        external
    {
        _decrease(msg.sender, market, side, sizeDelta);
    }

    /// @notice Router-gated decrease on behalf of `account`.
    function decreasePositionFor(address account, bytes32 market, DataTypes.Side side, uint256 sizeDelta)
        external
        onlyRouter
    {
        _decrease(account, market, side, sizeDelta);
    }

    /// @notice Fully closes the caller's position on a market/side.
    function closePosition(bytes32 market, DataTypes.Side side) external {
        bytes32 key = positionKey(msg.sender, market, side);
        uint256 size = _positions[key].size;
        if (size == 0) revert NoPosition(key);
        _decrease(msg.sender, market, side, size);
    }

    /// @dev Shared close logic. `account` is resolved by the caller, never from an
    ///      external self-call (which would rewrite msg.sender to this contract).
    function _decrease(
        address account,
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta
    ) private {
        if (sizeDelta == 0) revert ZeroSize();
        bytes32 key = positionKey(account, market, side);
        DataTypes.Position storage p = _positions[key];
        if (p.size == 0) revert NoPosition(key);
        if (sizeDelta > p.size) revert SizeExceedsPosition(sizeDelta, p.size);

        uint256 price = priceFeed.getPrice(market);

        // Collateral released proportional to the closed size.
        uint256 collateralPortion = (p.collateral * sizeDelta) / p.size;

        // Realized PnL on just the closed portion (PnL is linear in size), net of any
        // funding owed on that portion. Funding flows through the pool, like price PnL.
        int256 pnl = _realizedPnl(p, market, side, sizeDelta, collateralPortion, price);

        uint256 fee = _openFee(market, side, sizeDelta);

        // Reduce open interest before external settlement.
        _checkAndUpdateOpenInterest(market, side, sizeDelta, false);

        // Update position state.
        p.size -= sizeDelta;
        p.collateral -= collateralPortion;
        if (p.size == 0) {
            p.status = DataTypes.PositionStatus.CLOSED;
        }

        collateralVault.settle(account, market, key, collateralPortion, pnl, fee);

        emit PositionDecreased(key, account, market, sizeDelta, pnl, price);
    }

    /// @dev Realized PnL on the closed portion, funding-adjusted when wired.
    function _realizedPnl(
        DataTypes.Position storage p,
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralPortion,
        uint256 price
    ) private view returns (int256 pnl) {
        DataTypes.Position memory closed = p;
        closed.size = sizeDelta;
        closed.collateral = collateralPortion;
        pnl = PositionLib.unrealizedPnl(closed, price);
        if (address(fundingEngine) != address(0)) {
            // Positive fundingOwed ⇒ trader pays ⇒ reduces realized PnL.
            pnl -= fundingEngine.fundingOwed(market, sizeDelta, side, p.entryFundingIndex);
        }
    }

    /// @notice Adds collateral to a position, reducing its leverage.
    function addCollateral(bytes32 market, DataTypes.Side side, uint256 amount) external {
        bytes32 key = positionKey(msg.sender, market, side);
        DataTypes.Position storage p = _positions[key];
        if (p.size == 0) revert NoPosition(key);
        collateralVault.addCollateral(msg.sender, market, key, amount);
        p.collateral += amount;
        emit CollateralAdded(key, amount);
    }

    /// @notice Removes collateral from a position, increasing its leverage.
    /// @dev Reverts if the resulting position would breach min-collateral or max-leverage.
    function removeCollateral(bytes32 market, DataTypes.Side side, uint256 amount) external {
        bytes32 key = positionKey(msg.sender, market, side);
        DataTypes.Position storage p = _positions[key];
        if (p.size == 0) revert NoPosition(key);
        uint256 newCollateral = p.collateral - amount; // reverts on underflow
        leverageController.validatePosition(market, p.size, newCollateral);
        collateralVault.removeCollateral(msg.sender, market, key, amount);
        p.collateral = newCollateral;
        emit CollateralRemoved(key, amount);
    }

    // --------------------------------------------------------------------- //
    //                               Views                                   //
    // --------------------------------------------------------------------- //

    function getPosition(address account, bytes32 market, DataTypes.Side side)
        external
        view
        returns (DataTypes.Position memory)
    {
        return _positions[positionKey(account, market, side)];
    }

    /// @notice Current leverage of a position at the latest mark (WAD).
    function getLeverage(address account, bytes32 market, DataTypes.Side side)
        external
        view
        returns (uint256)
    {
        DataTypes.Position memory p = _positions[positionKey(account, market, side)];
        if (p.size == 0) return 0;
        return p.leverage(priceFeed.getPrice(market));
    }

    /// @notice Whether a position's equity has fallen below its maintenance margin.
    /// @dev Funding-aware when a {FundingRateEngine} is wired: the funding owed on the
    ///      whole position is subtracted from equity before the maintenance comparison.
    function isLiquidatable(address account, bytes32 market, DataTypes.Side side)
        public
        view
        returns (bool)
    {
        DataTypes.Position memory p = _positions[positionKey(account, market, side)];
        if (p.size == 0) return false;
        uint256 price = priceFeed.getPrice(market);
        uint256 maintenanceBps = leverageController.maintenanceMarginBps(market);
        if (address(fundingEngine) == address(0)) {
            return PositionLib.isLiquidatable(p, price, maintenanceBps);
        }
        int256 fundingOwed = fundingEngine.fundingOwed(market, p.size, side, p.entryFundingIndex);
        return PositionLib.isLiquidatableWithFunding(p, price, maintenanceBps, fundingOwed);
    }

    /// @notice Force-closes an unhealthy position. Callable only by LIQUIDATOR_ROLE
    ///         (the LiquidationEngine), which passes the keeper to be rewarded.
    function liquidate(address account, bytes32 market, DataTypes.Side side, address keeper)
        external
    {
        if (!roles.hasRole(roles.LIQUIDATOR_ROLE(), msg.sender)) {
            revert NotLiquidator(msg.sender);
        }
        bytes32 key = positionKey(account, market, side);
        DataTypes.Position storage p = _positions[key];
        if (p.size == 0) revert NoPosition(key);

        uint256 price = priceFeed.getPrice(market);
        uint256 maintenanceBps = leverageController.maintenanceMarginBps(market);
        int256 pnl = PositionLib.unrealizedPnl(p, price);
        if (address(fundingEngine) != address(0)) {
            int256 fundingOwed = fundingEngine.fundingOwed(market, p.size, side, p.entryFundingIndex);
            if (!PositionLib.isLiquidatableWithFunding(p, price, maintenanceBps, fundingOwed)) {
                revert NotLiquidatable(key);
            }
            pnl -= fundingOwed;
        } else if (!PositionLib.isLiquidatable(p, price, maintenanceBps)) {
            revert NotLiquidatable(key);
        }

        uint256 size = p.size;
        uint256 collateral = p.collateral;
        uint256 liqFee = size.bps(leverageController.getMarketConfig(market).liquidationFeeBps);

        // Wind down open interest and clear the position before external settlement.
        _checkAndUpdateOpenInterest(market, side, size, false);
        p.size = 0;
        p.collateral = 0;
        p.status = DataTypes.PositionStatus.LIQUIDATED;

        collateralVault.liquidate(
            CollateralVault.LiquidationParams({
                account: account,
                market: market,
                key: key,
                collateral: collateral,
                pnl: pnl,
                liquidationFee: liqFee,
                keeper: keeper
            })
        );

        emit PositionLiquidated(key, account, market, keeper, size, pnl, price);
    }

    function _checkAndUpdateOpenInterest(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        bool increase
    ) private {
        if (side == DataTypes.Side.LONG) {
            if (increase) {
                uint256 next = longOpenInterest[market] + sizeDelta;
                uint256 cap = leverageController.maxOpenInterest(market);
                if (next > cap) revert OpenInterestCap(market, next, cap);
                longOpenInterest[market] = next;
            } else {
                longOpenInterest[market] -= sizeDelta;
            }
        } else {
            if (increase) {
                uint256 next = shortOpenInterest[market] + sizeDelta;
                uint256 cap = leverageController.maxOpenInterest(market);
                if (next > cap) revert OpenInterestCap(market, next, cap);
                shortOpenInterest[market] = next;
            } else {
                shortOpenInterest[market] -= sizeDelta;
            }
        }
    }
}