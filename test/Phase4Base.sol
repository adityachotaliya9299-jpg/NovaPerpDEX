// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase2Base} from "./Phase2Base.sol";
import {InsuranceFund} from "../src/core/InsuranceFund.sol";
import {BadDebtHandler} from "../src/core/BadDebtHandler.sol";
import {LiquidationEngine} from "../src/core/LiquidationEngine.sol";
import {LiquidationBot} from "../src/core/LiquidationBot.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

/// @title Phase4Base
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Extends the Phase 2 margin stack with the liquidation system: insurance
///         fund, bad-debt handler, liquidation engine and batch bot — all wired and
///         with a seeded insurance reserve.
contract Phase4Base is Phase2Base {
    InsuranceFund internal insurance;
    BadDebtHandler internal badDebt;
    LiquidationEngine internal engine;
    LiquidationBot internal bot;

    address internal liquidator = makeAddr("liquidator");
    address internal botBeneficiary = makeAddr("botBeneficiary");

    uint256 internal constant KEEPER_REWARD_BPS = 2_000; // 20% of the liquidation fee
    uint256 internal constant INSURANCE_SEED = 100_000e18;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);
        badDebt = new BadDebtHandler(address(roles));
        insurance = new InsuranceFund(address(roles), address(vault), address(usd));
        engine = new LiquidationEngine(address(roles), address(mm));
        bot = new LiquidationBot(address(mm), address(engine), botBeneficiary);

        // Roles: insurance locks its own funds; engine performs liquidations.
        roles.grantRole(roles.OPERATOR_ROLE(), address(insurance));
        roles.grantRole(roles.OPERATOR_ROLE(), address(badDebt));
        roles.grantRole(roles.LIQUIDATOR_ROLE(), address(engine));

        // Wire the collateral vault's liquidation routing.
        cvault.setInsuranceFund(address(insurance));
        cvault.setBadDebtHandler(address(badDebt));
        cvault.setKeeperRewardBps(KEEPER_REWARD_BPS);

        // Seed the insurance fund.
        usd.mint(admin, INSURANCE_SEED);
        usd.approve(address(insurance), INSURANCE_SEED);
        insurance.seed(INSURANCE_SEED);
        vm.stopPrank();
    }

    DataTypes.Side internal constant LONG = DataTypes.Side.LONG;
    DataTypes.Side internal constant SHORT = DataTypes.Side.SHORT;

    function _openLong(address who, uint256 size, uint256 collateral) internal {
        vm.prank(who);
        mm.increasePosition(ETH_USD, LONG, size, collateral);
    }

    function _openShort(address who, uint256 size, uint256 collateral) internal {
        vm.prank(who);
        mm.increasePosition(ETH_USD, SHORT, size, collateral);
    }
}