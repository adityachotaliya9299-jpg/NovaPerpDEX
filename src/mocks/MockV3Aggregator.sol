// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title MockV3Aggregator
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Settable Chainlink-style aggregator for tests.
/// @dev Lets tests drive answer, decimals, round id and timestamps to exercise the
///      adapter's staleness, sign and round-completeness checks.
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _roundId = 1;
        _answeredInRound = 1;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "MockV3Aggregator";
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    /// @notice Sets a fresh answer and bumps the round (updatedAt = now).
    function updateAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
        _roundId += 1;
        _answeredInRound = _roundId;
    }

    /// @notice Sets a full round explicitly (for staleness / incomplete-round tests).
    function setRoundData(int256 answer, uint256 updatedAt, uint80 roundId, uint80 answeredInRound)
        external
    {
        _answer = answer;
        _updatedAt = updatedAt;
        _roundId = roundId;
        _answeredInRound = answeredInRound;
    }
}