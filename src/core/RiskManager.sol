// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Math} from "../libraries/Math.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title RiskManager
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Per-market skew limits and skew-scaled dynamic fees.
contract RiskManager {
    using Math for uint256;

    RoleManager public immutable roles;

    uint256 public constant MAX_BASE_FEE_BPS = 100;
    uint256 public constant MAX_DYNAMIC_FACTOR_BPS = 500;

    struct RiskConfig {
        uint256 maxSkewBps;
        uint256 baseFeeBps;
        uint256 dynamicFactorBps;
        bool configured;
    }

    mapping(bytes32 => RiskConfig) private _configs;

    event RiskConfigured(bytes32 indexed market, RiskConfig config);

    error NotGovernor(address caller);
    error NotConfigured(bytes32 market);
    error BaseFeeTooHigh(uint256 bps);
    error DynamicFactorTooHigh(uint256 bps);
    error SkewLimitExceeded(bytes32 market, uint256 postSkewBps, uint256 maxSkewBps);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager) {
        require(roleManager != address(0), "RM: zero roles");
        roles = RoleManager(roleManager);
    }

    function setRiskConfig(bytes32 market, RiskConfig calldata config) external onlyGovernor {
        if (config.baseFeeBps > MAX_BASE_FEE_BPS) revert BaseFeeTooHigh(config.baseFeeBps);
        if (config.dynamicFactorBps > MAX_DYNAMIC_FACTOR_BPS) {
            revert DynamicFactorTooHigh(config.dynamicFactorBps);
        }
        RiskConfig memory c = config;
        c.configured = true;
        _configs[market] = c;
        emit RiskConfigured(market, c);
    }

    function feeBps(bytes32 market, DataTypes.Side side, uint256 sizeDelta, uint256 longOi, uint256 shortOi)
        external
        view
        returns (uint256)
    {
        RiskConfig memory c = _configs[market];
        if (!c.configured) revert NotConfigured(market);

        (uint256 preImb, uint256 postImb, uint256 postTotal) =
            _imbalance(side, sizeDelta, longOi, shortOi);

        if (postImb <= preImb || postTotal == 0) {
            return c.baseFeeBps;
        }
        uint256 postSkewBps = postImb * Math.BPS_DENOMINATOR / postTotal;
        return c.baseFeeBps + c.dynamicFactorBps.bps(postSkewBps);
    }

    function validateSkew(bytes32 market, DataTypes.Side side, uint256 sizeDelta, uint256 longOi, uint256 shortOi)
        external
        view
    {
        RiskConfig memory c = _configs[market];
        if (!c.configured) revert NotConfigured(market);
        if (c.maxSkewBps == 0) return;

        (uint256 preImb, uint256 postImb, uint256 postTotal) =
            _imbalance(side, sizeDelta, longOi, shortOi);
        if (postTotal == 0) return;
        uint256 postSkewBps = postImb * Math.BPS_DENOMINATOR / postTotal;
        if (postSkewBps > c.maxSkewBps && postImb > preImb) {
            revert SkewLimitExceeded(market, postSkewBps, c.maxSkewBps);
        }
    }

    function getRiskConfig(bytes32 market) external view returns (RiskConfig memory) {
        return _configs[market];
    }

    function isConfigured(bytes32 market) external view returns (bool) {
        return _configs[market].configured;
    }

    function _imbalance(DataTypes.Side side, uint256 sizeDelta, uint256 longOi, uint256 shortOi)
        private
        pure
        returns (uint256 preImb, uint256 postImb, uint256 postTotal)
    {
        uint256 postLong = side == DataTypes.Side.LONG ? longOi + sizeDelta : longOi;
        uint256 postShort = side == DataTypes.Side.SHORT ? shortOi + sizeDelta : shortOi;
        preImb = Math.absDiff(longOi, shortOi);
        postImb = Math.absDiff(postLong, postShort);
        postTotal = postLong + postShort;
    }
}