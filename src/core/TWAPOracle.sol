// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RoleManager} from "./RoleManager.sol";

/// @title TWAPOracle
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Maintains a time-weighted average price per market from keeper-recorded
///         spot observations, à la Uniswap V2 cumulative prices.
/// @dev Each `record` accrues `lastPrice * elapsed` into a running cumulative, so a
///      TWAP over a window is `(cumulativeNow - cumulativeThen) / elapsed`. Because a
///      single spike contributes only in proportion to the time it persists, a TWAP
///      is expensive to manipulate — an attacker must hold the price for the window.
contract TWAPOracle {
    RoleManager public immutable roles;

    struct Observation {
        uint256 timestamp;
        uint256 cumulativePrice; // sum of price * dt up to `timestamp`
    }

    /// @notice market => last recorded spot price (WAD).
    mapping(bytes32 => uint256) public lastPrice;

    /// @notice market => ordered observations (oldest first).
    mapping(bytes32 => Observation[]) private _obs;

    event Recorded(bytes32 indexed market, uint256 price, uint256 cumulative, uint256 timestamp);

    error NotPriceKeeper(address caller);
    error ZeroPrice();
    error NoObservations(bytes32 market);
    error WindowTooLong(bytes32 market, uint256 window, uint256 available);

    modifier onlyKeeper() {
        if (!roles.hasRole(roles.PRICE_KEEPER_ROLE(), msg.sender)) {
            revert NotPriceKeeper(msg.sender);
        }
        _;
    }

    constructor(address roleManager) {
        require(roleManager != address(0), "TWAP: zero roles");
        roles = RoleManager(roleManager);
    }

    /// @notice Records a new spot observation for a market. Keeper-only.
    function record(bytes32 market, uint256 price) external onlyKeeper {
        if (price == 0) revert ZeroPrice();
        Observation[] storage series = _obs[market];

        if (series.length == 0) {
            series.push(Observation({timestamp: block.timestamp, cumulativePrice: 0}));
        } else {
            Observation memory last = series[series.length - 1];
            uint256 elapsed = block.timestamp - last.timestamp;
            uint256 newCumulative = last.cumulativePrice + lastPrice[market] * elapsed;
            series.push(Observation({timestamp: block.timestamp, cumulativePrice: newCumulative}));
            emit Recorded(market, price, newCumulative, block.timestamp);
        }
        lastPrice[market] = price;
    }

    /// @notice Time-weighted average price over the last `window` seconds.
    /// @dev Extrapolates the cumulative to `block.timestamp` using the last price,
    ///      then differences against the observation at/just-before `now - window`.
    function consult(bytes32 market, uint256 window) external view returns (uint256) {
        Observation[] storage series = _obs[market];
        uint256 n = series.length;
        if (n == 0) revert NoObservations(market);

        Observation memory last = series[n - 1];
        uint256 nowCumulative = last.cumulativePrice + lastPrice[market] * (block.timestamp - last.timestamp);

        uint256 target = block.timestamp - window;
        if (target < series[0].timestamp) {
            revert WindowTooLong(market, window, block.timestamp - series[0].timestamp);
        }

        // Find the latest observation with timestamp <= target (linear; series is small).
        uint256 i = n;
        while (i > 0) {
            i--;
            if (series[i].timestamp <= target) break;
        }
        Observation memory anchor = series[i];

        // Cumulative at `target`, interpolated within the [anchor, next] segment.
        uint256 priceDuringSegment = (i + 1 < n)
            ? _segmentPrice(series[i], series[i + 1])
            : lastPrice[market];
        uint256 targetCumulative =
            anchor.cumulativePrice + priceDuringSegment * (target - anchor.timestamp);

        return (nowCumulative - targetCumulative) / window;
    }

    function observationCount(bytes32 market) external view returns (uint256) {
        return _obs[market].length;
    }

    /// @dev Derives the constant spot price held over a [a, b] segment from the
    ///      cumulative delta (cumulative is piecewise-linear between observations).
    function _segmentPrice(Observation memory a, Observation memory b)
        internal
        pure
        returns (uint256)
    {
        uint256 dt = b.timestamp - a.timestamp;
        if (dt == 0) return 0;
        return (b.cumulativePrice - a.cumulativePrice) / dt;
    }
}