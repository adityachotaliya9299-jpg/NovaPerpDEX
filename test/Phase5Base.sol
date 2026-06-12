// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase4Base} from "./Phase4Base.sol";
import {FundingRateEngine} from "../src/core/FundingRateEngine.sol";
import {RiskManager} from "../src/core/RiskManager.sol";
import {PositionRouter} from "../src/core/PositionRouter.sol";
import {OrderBook} from "../src/core/OrderBook.sol";
import {StopLossManager} from "../src/core/StopLossManager.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

/// @title Phase5Base
/// @notice Extends the Phase 4 stack with funding, risk management and the execution
///         contracts (router, order book, stop-loss), all wired into the MarginManager.
/// @dev Funding is initialized with a ZERO max rate so it is neutral by default — tests
///      that exercise funding opt in via `funding.setMaxRate`. The RiskManager is wired
///      as a pass-through (10bps base, no surcharge, no skew limit) so trade fees match
///      earlier phases; RiskManager-specific tests reconfigure it.
contract Phase5Base is Phase4Base {
    FundingRateEngine internal funding;
    RiskManager internal risk;
    PositionRouter internal router;
    OrderBook internal orderBook;
    StopLossManager internal stopLoss;

    uint256 internal constant FUNDING_MAX_RATE = 1e12; // used when tests opt in

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);
        funding = new FundingRateEngine(address(roles));
        funding.setOpenInterestSource(address(mm));
        funding.initializeMarket(ETH_USD, 0); // neutral by default

        risk = new RiskManager(address(roles));
        risk.setRiskConfig(
            ETH_USD,
            RiskManager.RiskConfig({
                maxSkewBps: 0, // no limit by default
                baseFeeBps: 10, // matches Phase 2 position fee
                dynamicFactorBps: 0, // no surcharge by default
                configured: false
            })
        );

        mm.setFundingEngine(address(funding));
        mm.setRiskManager(address(risk));

        router = new PositionRouter(address(roles), address(mm));
        router.setFundingEngine(address(funding));
        orderBook = new OrderBook(address(priceFeed), address(mm));
        stopLoss = new StopLossManager(address(priceFeed), address(mm));

        mm.setRouter(address(router), true);
        mm.setRouter(address(orderBook), true);
        mm.setRouter(address(stopLoss), true);
        vm.stopPrank();
    }

    /// @notice Enables funding at the standard rate and anchors the index at `now`.
    function _enableFunding() internal {
        vm.prank(admin);
        funding.setMaxRate(ETH_USD, FUNDING_MAX_RATE);
        funding.updateFunding(ETH_USD);
    }
}