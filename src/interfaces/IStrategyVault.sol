// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IStrategyVault
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice External interface for StrategyVault — used by StrategyFactory,
///         StrategyRegistry, and the frontend ABI generator.
interface IStrategyVault {
    // ------------------------------------------------------------------ //
    //                              Events                                 //
    // ------------------------------------------------------------------ //

    event Deposit(address indexed investor, uint256 assets, uint256 shares);
    event Withdraw(address indexed investor, uint256 assets, uint256 shares);
    event AgentTraded(
        bytes32 indexed market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta,
        bool isIncrease,
        string reason
    );
    event DrawdownBreached(uint256 currentDrawdownBps, uint256 limitBps);
    event AgentWalletSet(address indexed agent);
    event TradingHalted(bool halted);
    event RiskParamsUpdated(
        uint256 maxDrawdownBps,
        uint256 maxLeverageBps,
        uint256 maxSinglePositionBps
    );
    event ProtocolFeeCollected(uint256 amount);
    event CreatorFeeCollected(uint256 amount);

    // ------------------------------------------------------------------ //
    //                              Errors                                 //
    // ------------------------------------------------------------------ //

    error ZeroAmount();
    error NotAgent(address caller);
    error NotCreator(address caller);
    error NotGovernor(address caller);
    error TradingIsHalted();
    error DrawdownLimitBreached(uint256 currentBps, uint256 limitBps);
    error MaxPositionSizeBreached(uint256 requestedBps, uint256 limitBps);
    error InsufficientShares(address investor, uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error BelowMinDeposit(uint256 amount, uint256 min);
    error InsufficientAllowance(address owner, address spender, uint256 req, uint256 avail);

    // ------------------------------------------------------------------ //
    //                           Investor API                              //
    // ------------------------------------------------------------------ //

    function deposit(uint256 assets) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 assets);

    // ------------------------------------------------------------------ //
    //                            Agent API                                //
    // ------------------------------------------------------------------ //

    function openPosition(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta,
        string calldata reason
    ) external;

    function closePosition(
        bytes32 market,
        DataTypes.Side side,
        string calldata reason
    ) external;

    function decreasePosition(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        string calldata reason
    ) external;

    // ------------------------------------------------------------------ //
    //                            Views                                    //
    // ------------------------------------------------------------------ //

    function totalAssets() external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function currentDrawdownBps() external view returns (uint256);
    function isHalted() external view returns (bool);

    // ------------------------------------------------------------------ //
    //                           ERC20-like shares                         //
    // ------------------------------------------------------------------ //

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}