// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "../Phase5Base.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title FundingIntegrationTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Verifies funding folds into realized PnL on close and into the liquidation
///         health check, routed through the pool so value stays conserved.
contract FundingIntegrationTest is Phase5Base {
    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000); // base timestamp so funding/price math is clean
        _setPrice(2_000e18); // re-anchor the feed's timestamp post-warp (avoids staleness)
    }

    function test_LongPaysFundingOnClose() public {
        _enableFunding(); // OI is 0 here, so the index anchors at 0
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 2_000e18); // entryFundingIndex snapshot = 0

        vm.warp(block.timestamp + 3_600); // 1h at full long-skew rate (1e12/s)
        _setPrice(2_000e18); // refresh oracle (price unchanged)

        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);

        // funding owed = size * (rate*elapsed) / WAD = 10000 * (1e12*3600)/1e18 = 36
        // net loss = open fee 10 + close fee 10 + funding 36 = 56
        assertEq(vault.balanceOf(alice), 100_000e18 - 56e18);
    }

    function test_NoFundingAdjustmentWhenRateZero() public {
        // funding left at the neutral zero rate from the base
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 2_000e18);
        vm.warp(block.timestamp + 3_600);
        _setPrice(2_000e18);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
        // only the two fees, no funding
        assertEq(vault.balanceOf(alice), 100_000e18 - 20e18);
    }

    function test_BalancedOpenInterestAccruesNoFunding() public {
        _enableFunding();
        _deposit(alice, 100_000e18);
        _deposit(bob, 100_000e18);
        _openLong(alice, 10_000e18, 2_000e18);
        _openShort(bob, 10_000e18, 2_000e18); // OI now balanced => rate 0

        vm.warp(block.timestamp + 3_600);
        _setPrice(2_000e18);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
        assertEq(vault.balanceOf(alice), 100_000e18 - 20e18); // no funding
    }

    function test_EntryFundingIndexSnapshotOnOpen() public {
        _enableFunding();
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 2_000e18);
        // opened in the same block the index was anchored => snapshot is 0
        assertEq(mm.getPosition(alice, ETH_USD, LONG).entryFundingIndex, int256(0));
    }

    function test_FundingMakesHealthyLongLiquidatable() public {
        _enableFunding();
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18); // 10x; price-only equity 1000 >> maintenance 200

        // healthy on price alone
        assertFalse(engine.isLiquidatable(alice, ETH_USD, LONG));

        // accrue funding until owed (~900) drags equity below maintenance (200)
        vm.warp(block.timestamp + 90_000);
        _setPrice(2_000e18); // price unchanged; refresh oracle

        assertTrue(engine.isLiquidatable(alice, ETH_USD, LONG));
    }

    function test_FundingDrivenLiquidationClears() public {
        _enableFunding();
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        vm.warp(block.timestamp + 90_000);
        _setPrice(2_000e18);

        vm.prank(liquidator);
        engine.liquidate(alice, ETH_USD, LONG);

        assertEq(mm.getPosition(alice, ETH_USD, LONG).size, 0);
        assertEq(mm.longOpenInterest(ETH_USD), 0);
    }

    function test_VaultStaysSolventThroughFunding() public {
        _enableFunding();
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 2_000e18);
        vm.warp(block.timestamp + 3_600);
        _setPrice(2_000e18);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
        // token balance always equals accounted total, funding flowed through the pool
        assertEq(usd.balanceOf(address(vault)), vault.totalCollateral());
    }
}