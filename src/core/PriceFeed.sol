// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title PriceFeed
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice A keeper-pushed price feed implementing {IPriceFeed}.
/// @dev In Phase 1 this is the canonical price source; in Phase 3 it is superseded
///      by an aggregator that blends Chainlink and an on-chain TWAP. Prices are
///      WAD (1e18) USD. Updates are gated by PRICE_KEEPER_ROLE and bounded by a
///      staleness window so consumers can reject prices that are too old.
contract PriceFeed is IPriceFeed {
    /// @notice Role registry used for authorization.
    RoleManager public immutable roles;

    /// @notice Maximum age (seconds) before a price is considered stale.
    uint256 public stalenessThreshold;

    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }

    /// @notice market => latest price data.
    mapping(bytes32 => PriceData) private _prices;

    error StalePrice(bytes32 market, uint256 updatedAt, uint256 nowTs);
    error ZeroPrice();
    error NotPriceKeeper(address caller);
    error NotGovernor(address caller);

    /// @param roleManager Address of the shared RoleManager.
    /// @param staleness_ Initial staleness threshold in seconds.
    constructor(address roleManager, uint256 staleness_) {
        require(roleManager != address(0), "PriceFeed: zero roles");
        require(staleness_ > 0, "PriceFeed: zero staleness");
        roles = RoleManager(roleManager);
        stalenessThreshold = staleness_;
    }

    /// @notice Pushes a new price for `market`. Keeper-only.
    /// @param market The market identifier.
    /// @param price The new price (WAD, must be non-zero).
    function setPrice(bytes32 market, uint256 price) external {
        if (!roles.hasRole(roles.PRICE_KEEPER_ROLE(), msg.sender)) {
            revert NotPriceKeeper(msg.sender);
        }
        if (price == 0) revert ZeroPrice();
        _prices[market] = PriceData({price: price, timestamp: block.timestamp});
        emit PriceUpdated(market, price, block.timestamp);
    }

    /// @inheritdoc IPriceFeed
    function getPrice(bytes32 market) external view returns (uint256) {
        PriceData memory data = _prices[market];
        if (data.timestamp == 0) revert ZeroPrice();
        if (block.timestamp - data.timestamp > stalenessThreshold) {
            revert StalePrice(market, data.timestamp, block.timestamp);
        }
        return data.price;
    }

    /// @inheritdoc IPriceFeed
    function lastUpdated(bytes32 market) external view returns (uint256) {
        return _prices[market].timestamp;
    }

    /// @notice Updates the staleness threshold. Governor-only.
    function setStalenessThreshold(uint256 newThreshold) external {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        require(newThreshold > 0, "PriceFeed: zero staleness");
        stalenessThreshold = newThreshold;
    }
}
