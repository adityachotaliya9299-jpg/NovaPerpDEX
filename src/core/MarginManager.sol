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

/// @title MarginManager
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice The trading entry point: opens, increases, decreases and closes leveraged
///         perpetual positions.
/// @dev Owns position state and open-interest accounting, reads marks from the
///      {IPriceFeed}, validates risk via {LeverageController}, prices fees via
///      {FeeDistributor}, and delegates *all* collateral movement to {CollateralVault}.
///      It never moves tokens itself — that separation keeps value conservation
///      provable in the CollateralVault alone.
contract MarginManager {
    using Math for uint256;
    using PositionLib for DataTypes.Position;

    RoleManager public immutable roles;
    IPriceFeed public immutable priceFeed;
    LeverageController public immutable leverageController;
    CollateralVault public immutable collateralVault;
    FeeDistributor public immutable feeDistributor;

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
        if (sizeDelta == 0) revert ZeroSize();
        address account = msg.sender;
        bytes32 key = positionKey(account, market, side);
        DataTypes.Position storage p = _positions[key];

        uint256 price = priceFeed.getPrice(market);
        uint256 newSize = p.size + sizeDelta;
        uint256 newCollateral = p.collateral + collateralDelta;

        // Risk checks on the resulting aggregate position.
        leverageController.validatePosition(market, newSize, newCollateral);
        _checkAndUpdateOpenInterest(market, side, sizeDelta, true);

        // Reserve collateral and charge the open fee.
        uint256 fee = feeDistributor.feeOnSize(sizeDelta);
        collateralVault.reserve(account, market, key, collateralDelta, fee);

        // Update position state (blended entry on increase).
        if (p.size == 0) {
            p.owner = account;
            p.market = market;
            p.side = side;
            p.entryPrice = price;
            p.status = DataTypes.PositionStatus.OPEN;
        } else {
            p.entryPrice =
                PositionLib.blendedEntryPrice(p.size, p.entryPrice, sizeDelta, price);
        }
        p.size = newSize;
        p.collateral = newCollateral;
        p.lastIncreasedAt = uint64(block.timestamp);

        emit PositionIncreased(key, account, market, side, sizeDelta, collateralDelta, price);
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

        // Realized PnL on just the closed portion (PnL is linear in size).
        DataTypes.Position memory closed = p;
        closed.size = sizeDelta;
        closed.collateral = collateralPortion;
        int256 pnl = PositionLib.unrealizedPnl(closed, price);

        uint256 fee = feeDistributor.feeOnSize(sizeDelta);

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
