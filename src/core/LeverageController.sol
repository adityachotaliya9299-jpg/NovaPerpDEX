// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Math} from "../libraries/Math.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title LeverageController
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Owns per-market risk configuration and validates leverage / collateral
///         constraints for the margin engine.
/// @dev Stateful registry of {DataTypes.MarketConfig}. The margin engine calls the
///      `validate*` functions on every position mutation. Keeping validation here
///      (rather than inline in MarginManager) means risk rules live in one auditable
///      place and can be tuned by governance without touching the trading logic.
contract LeverageController {
    using Math for uint256;

    /// @notice Shared role registry.
    RoleManager public immutable roles;

    /// @notice Global minimum collateral (WAD USD) required to open a position.
    uint256 public minCollateral;

    /// @notice market => configuration.
    mapping(bytes32 => DataTypes.MarketConfig) private _configs;

    /// @notice market => whether it has been registered.
    mapping(bytes32 => bool) private _exists;

    /// @notice Enumerable list of registered markets.
    bytes32[] public markets;

    event MarketAdded(bytes32 indexed market, DataTypes.MarketConfig config);
    event MarketUpdated(bytes32 indexed market, DataTypes.MarketConfig config);
    event MarketActiveSet(bytes32 indexed market, bool isActive);
    event MinCollateralSet(uint256 minCollateral);

    error NotGovernor(address caller);
    error MarketExists(bytes32 market);
    error MarketUnknown(bytes32 market);
    error MarketInactive(bytes32 market);
    error InvalidConfig();
    error ZeroSize();
    error CollateralTooLow(uint256 collateral, uint256 minimum);
    error LeverageTooHigh(uint256 leverage, uint256 maxLeverage);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    /// @param roleManager Address of the shared RoleManager.
    /// @param minCollateral_ Initial global minimum collateral (WAD USD).
    constructor(address roleManager, uint256 minCollateral_) {
        require(roleManager != address(0), "LC: zero roles");
        roles = RoleManager(roleManager);
        minCollateral = minCollateral_;
    }

    /// @notice Registers a new market. Governor-only.
    function addMarket(bytes32 market, DataTypes.MarketConfig calldata config)
        external
        onlyGovernor
    {
        if (_exists[market]) revert MarketExists(market);
        _validateConfig(config);
        _configs[market] = config;
        _exists[market] = true;
        markets.push(market);
        emit MarketAdded(market, config);
    }

    /// @notice Updates an existing market's configuration. Governor-only.
    function setMarketConfig(bytes32 market, DataTypes.MarketConfig calldata config)
        external
        onlyGovernor
    {
        if (!_exists[market]) revert MarketUnknown(market);
        _validateConfig(config);
        _configs[market] = config;
        emit MarketUpdated(market, config);
    }

    /// @notice Toggles a market active/inactive. Governor-only.
    function setMarketActive(bytes32 market, bool active) external onlyGovernor {
        if (!_exists[market]) revert MarketUnknown(market);
        _configs[market].isActive = active;
        emit MarketActiveSet(market, active);
    }

    /// @notice Updates the global minimum collateral. Governor-only.
    function setMinCollateral(uint256 newMin) external onlyGovernor {
        minCollateral = newMin;
        emit MinCollateralSet(newMin);
    }

    /// @notice Validates that opening/holding `size` against `collateral` on `market`
    ///         satisfies the active, min-collateral and max-leverage constraints.
    /// @dev Reverts with a specific error on any violation. Called by MarginManager.
    function validatePosition(bytes32 market, uint256 size, uint256 collateral)
        external
        view
    {
        if (!_exists[market]) revert MarketUnknown(market);
        DataTypes.MarketConfig memory cfg = _configs[market];
        if (!cfg.isActive) revert MarketInactive(market);
        if (size == 0) revert ZeroSize();
        if (collateral < minCollateral) revert CollateralTooLow(collateral, minCollateral);
        uint256 lev = size.wdiv(collateral);
        if (lev > cfg.maxLeverage) revert LeverageTooHigh(lev, cfg.maxLeverage);
    }

    /// @notice Returns the full configuration for a market.
    function getMarketConfig(bytes32 market)
        external
        view
        returns (DataTypes.MarketConfig memory)
    {
        if (!_exists[market]) revert MarketUnknown(market);
        return _configs[market];
    }

    function exists(bytes32 market) external view returns (bool) {
        return _exists[market];
    }

    function isActive(bytes32 market) external view returns (bool) {
        return _configs[market].isActive;
    }

    function maxLeverage(bytes32 market) external view returns (uint256) {
        return _configs[market].maxLeverage;
    }

    function maintenanceMarginBps(bytes32 market) external view returns (uint256) {
        return _configs[market].maintenanceMarginBps;
    }

    function maxOpenInterest(bytes32 market) external view returns (uint256) {
        return _configs[market].maxOpenInterest;
    }

    function marketCount() external view returns (uint256) {
        return markets.length;
    }

    function _validateConfig(DataTypes.MarketConfig calldata config) private pure {
        if (config.maxLeverage < Math.WAD) revert InvalidConfig(); // at least 1x
        if (config.maintenanceMarginBps == 0) revert InvalidConfig();
        if (config.maintenanceMarginBps >= Math.BPS_DENOMINATOR) revert InvalidConfig();
        if (config.liquidationFeeBps >= Math.BPS_DENOMINATOR) revert InvalidConfig();
        if (config.maxOpenInterest == 0) revert InvalidConfig();
    }
}
