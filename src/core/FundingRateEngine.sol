// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Math} from "../libraries/Math.sol";
import {IOpenInterest} from "../interfaces/IOpenInterest.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title FundingRateEngine
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Computes and accrues perpetual funding based on long/short open-interest
///         skew, the mechanism that tethers the perp price to the index.
/// @dev Funding accrues into a per-market cumulative index (signed, WAD). A position
///      snapshots the index at entry; on close it owes `size * (indexNow - indexEntry)`.
///      A positive index growth means longs pay shorts (longs are crowded). The rate
///      is `maxFundingRatePerSecond * normalizedSkew`, where the skew is bounded to
///      [-1, 1], so the rate is bounded to [-max, max]. `updateFunding` is permissionless.
contract FundingRateEngine {
    using Math for uint256;

    RoleManager public immutable roles;

    /// @notice Source of per-market open interest (the MarginManager).
    IOpenInterest public openInterest;

    struct FundingState {
        int256 cumulativeIndex; // WAD, signed
        uint256 lastUpdated; // timestamp of last persisted update
        uint256 maxRatePerSecond; // WAD cap on |rate| per second
        bool initialized;
    }

    /// @notice market => funding state.
    mapping(bytes32 => FundingState) private _state;

    event MarketInitialized(bytes32 indexed market, uint256 maxRatePerSecond);
    event MaxRateSet(bytes32 indexed market, uint256 maxRatePerSecond);
    event FundingUpdated(bytes32 indexed market, int256 cumulativeIndex, int256 ratePerSecond);
    event OpenInterestSourceSet(address source);

    error NotGovernor(address caller);
    error MarketNotInitialized(bytes32 market);
    error SourceNotSet();

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager) {
        require(roleManager != address(0), "FRE: zero roles");
        roles = RoleManager(roleManager);
    }

    /// @notice Sets the open-interest source. Governor-only.
    function setOpenInterestSource(address source) external onlyGovernor {
        require(source != address(0), "FRE: zero source");
        openInterest = IOpenInterest(source);
        emit OpenInterestSourceSet(source);
    }

    /// @notice Initializes funding for a market. Governor-only.
    function initializeMarket(bytes32 market, uint256 maxRatePerSecond) external onlyGovernor {
        FundingState storage s = _state[market];
        s.maxRatePerSecond = maxRatePerSecond;
        s.lastUpdated = block.timestamp;
        s.initialized = true;
        emit MarketInitialized(market, maxRatePerSecond);
    }

    /// @notice Updates the funding cap for a market. Governor-only.
    function setMaxRate(bytes32 market, uint256 maxRatePerSecond) external onlyGovernor {
        if (!_state[market].initialized) revert MarketNotInitialized(market);
        _state[market].maxRatePerSecond = maxRatePerSecond;
        emit MaxRateSet(market, maxRatePerSecond);
    }

    /// @notice Current per-second funding rate (signed WAD). Positive ⇒ longs pay shorts.
    function currentFundingRate(bytes32 market) public view returns (int256) {
        if (address(openInterest) == address(0)) revert SourceNotSet();
        FundingState memory s = _state[market];
        if (!s.initialized) revert MarketNotInitialized(market);

        uint256 longOi = openInterest.longOpenInterest(market);
        uint256 shortOi = openInterest.shortOpenInterest(market);
        uint256 total = longOi + shortOi;
        if (total == 0) return 0;

        // normalizedSkew ∈ [-WAD, WAD]
        int256 skew = int256(longOi) - int256(shortOi);
        int256 normalizedSkew = (skew * int256(Math.WAD)) / int256(total);

        // rate = maxRate * normalizedSkew / WAD ∈ [-maxRate, maxRate]
        return (int256(s.maxRatePerSecond) * normalizedSkew) / int256(Math.WAD);
    }

    /// @notice The funding index extrapolated to the current block, without persisting.
    function pendingIndex(bytes32 market) public view returns (int256) {
        FundingState memory s = _state[market];
        if (!s.initialized) revert MarketNotInitialized(market);
        int256 rate = currentFundingRate(market);
        uint256 elapsed = block.timestamp - s.lastUpdated;
        return s.cumulativeIndex + rate * int256(elapsed);
    }

    /// @notice Persists funding accrual up to the current block. Permissionless.
    function updateFunding(bytes32 market) external returns (int256) {
        FundingState storage s = _state[market];
        if (!s.initialized) revert MarketNotInitialized(market);
        int256 rate = currentFundingRate(market);
        uint256 elapsed = block.timestamp - s.lastUpdated;
        s.cumulativeIndex += rate * int256(elapsed);
        s.lastUpdated = block.timestamp;
        emit FundingUpdated(market, s.cumulativeIndex, rate);
        return s.cumulativeIndex;
    }

    /// @notice Funding owed by a position since its entry snapshot (signed WAD USD).
    /// @dev Positive ⇒ the position pays; negative ⇒ the position receives. For a LONG,
    ///      a rising index means it pays; a SHORT's sign is mirrored.
    function fundingOwed(
        bytes32 market,
        uint256 size,
        DataTypes.Side side,
        int256 entryIndex
    ) external view returns (int256) {
        int256 deltaIndex = pendingIndex(market) - entryIndex;
        // size * deltaIndex / WAD, with sign by side.
        int256 longOwed = (int256(size) * deltaIndex) / int256(Math.WAD);
        return side == DataTypes.Side.LONG ? longOwed : -longOwed;
    }

    /// @notice Current persisted cumulative index.
    function cumulativeIndex(bytes32 market) external view returns (int256) {
        return _state[market].cumulativeIndex;
    }

    function getState(bytes32 market) external view returns (FundingState memory) {
        return _state[market];
    }
}