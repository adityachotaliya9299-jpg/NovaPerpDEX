// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOpenInterest} from "../interfaces/IOpenInterest.sol";

/// @title MockOpenInterest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Settable open-interest source so the FundingRateEngine can be tested
///         without deploying the full MarginManager.
contract MockOpenInterest is IOpenInterest {
    mapping(bytes32 => uint256) private _long;
    mapping(bytes32 => uint256) private _short;

    function setOpenInterest(bytes32 market, uint256 longOi, uint256 shortOi) external {
        _long[market] = longOi;
        _short[market] = shortOi;
    }

    function longOpenInterest(bytes32 market) external view returns (uint256) {
        return _long[market];
    }

    function shortOpenInterest(bytes32 market) external view returns (uint256) {
        return _short[market];
    }
}