// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DataTypes} from "../libraries/DataTypes.sol";
import {MarginManager} from "./MarginManager.sol";
import {LiquidationEngine} from "./LiquidationEngine.sol";

/// @title LiquidationBot
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice On-chain batch keeper: scans a set of accounts and liquidates the eligible
///         ones in a single transaction, directing all keeper rewards to one recipient.
/// @dev A convenience wrapper over {LiquidationEngine}. Eligibility is checked per
///      account so a non-liquidatable entry is skipped rather than reverting the batch.
contract LiquidationBot {
    MarginManager public immutable marginManager;
    LiquidationEngine public immutable engine;

    /// @notice The address credited with keeper rewards from this bot's liquidations.
    address public immutable rewardRecipient;

    event BatchLiquidated(bytes32 indexed market, DataTypes.Side side, uint256 count);

    constructor(address marginManager_, address engine_, address rewardRecipient_) {
        require(marginManager_ != address(0), "BOT: zero mm");
        require(engine_ != address(0), "BOT: zero engine");
        require(rewardRecipient_ != address(0), "BOT: zero recipient");
        marginManager = MarginManager(marginManager_);
        engine = LiquidationEngine(engine_);
        rewardRecipient = rewardRecipient_;
    }

    /// @notice Liquidates every eligible account in `accounts` for one market/side.
    /// @return count The number of positions successfully liquidated.
    function liquidateBatch(address[] calldata accounts, bytes32 market, DataTypes.Side side)
        external
        returns (uint256 count)
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (!marginManager.isLiquidatable(accounts[i], market, side)) continue;
            try engine.liquidateFor(accounts[i], market, side, rewardRecipient) {
                count++;
            } catch {
                // Skip positions that became unliquidatable between the check and call.
            }
        }
        emit BatchLiquidated(market, side, count);
    }

    /// @notice Returns the count and list of liquidatable accounts (view helper for keepers).
    function liquidatableAccounts(address[] calldata accounts, bytes32 market, DataTypes.Side side)
        external
        view
        returns (address[] memory eligible)
    {
        uint256 n;
        address[] memory tmp = new address[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            if (marginManager.isLiquidatable(accounts[i], market, side)) {
                tmp[n] = accounts[i];
                n++;
            }
        }
        eligible = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            eligible[i] = tmp[i];
        }
    }
}