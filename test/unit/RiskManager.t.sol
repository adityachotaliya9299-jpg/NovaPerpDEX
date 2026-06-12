// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "../Phase5Base.sol";
import {RiskManager} from "../../src/core/RiskManager.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @title RiskManagerTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Unit + fuzz tests for skew limits and skew-scaled dynamic fees.
contract RiskManagerTest is Phase5Base {
    function _config(uint256 maxSkew, uint256 base, uint256 dynamic) internal {
        vm.prank(admin);
        risk.setRiskConfig(
            ETH_USD,
            RiskManager.RiskConfig({
                maxSkewBps: maxSkew,
                baseFeeBps: base,
                dynamicFactorBps: dynamic,
                configured: false
            })
        );
    }

    // ------------------------------ config ----------------------------- //

    function test_ConfiguredInSetup() public view {
        assertTrue(risk.isConfigured(ETH_USD));
    }

    function test_GovernorCanConfigure() public {
        _config(5_000, 10, 100);
        RiskManager.RiskConfig memory c = risk.getRiskConfig(ETH_USD);
        assertEq(c.maxSkewBps, 5_000);
        assertEq(c.baseFeeBps, 10);
        assertEq(c.dynamicFactorBps, 100);
    }

    function test_RevertWhen_NonGovernorConfigures() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RiskManager.NotGovernor.selector, alice));
        risk.setRiskConfig(
            ETH_USD, RiskManager.RiskConfig(0, 10, 0, false)
        );
    }

    function test_RevertWhen_BaseFeeTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RiskManager.BaseFeeTooHigh.selector, 101));
        risk.setRiskConfig(ETH_USD, RiskManager.RiskConfig(0, 101, 0, false));
    }

    function test_RevertWhen_DynamicFactorTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RiskManager.DynamicFactorTooHigh.selector, 501));
        risk.setRiskConfig(ETH_USD, RiskManager.RiskConfig(0, 10, 501, false));
    }

    function test_RevertWhen_FeeBpsUnconfiguredMarket() public {
        bytes32 btc = keccak256("BTC-USD");
        vm.expectRevert(abi.encodeWithSelector(RiskManager.NotConfigured.selector, btc));
        risk.feeBps(btc, LONG, 1_000e18, 0, 0);
    }

    // ------------------------------ fees ------------------------------- //

    function test_BaseFeeWhenBalancing() public {
        _config(0, 10, 100);
        // long-heavy book; a short reduces imbalance => base fee only
        assertEq(risk.feeBps(ETH_USD, SHORT, 500e18, 1_000e18, 0), 10);
    }

    function test_SurchargeWhenWorseningSkew() public {
        _config(0, 10, 100);
        // open long into an empty book => 100% post-skew => surcharge 100 * 100% = 100bps
        assertEq(risk.feeBps(ETH_USD, LONG, 1_000e18, 0, 0), 110);
    }

    function test_PartialSurcharge() public {
        _config(0, 10, 100);
        // long 500 onto balanced 1000/1000 => post 1500/1000, skew 500/2500 = 20%
        // surcharge = 100 * 20% = 20 => fee 30
        assertEq(risk.feeBps(ETH_USD, LONG, 500e18, 1_000e18, 1_000e18), 30);
    }

    function test_BaseFeeWhenZeroDynamicFactor() public {
        _config(0, 10, 0);
        assertEq(risk.feeBps(ETH_USD, LONG, 1_000e18, 0, 0), 10);
    }

    // ------------------------------ skew ------------------------------- //

    function test_SkewWithinLimitPasses() public {
        _config(5_000, 10, 0); // 50% max
        // balanced book, long 500 => post-skew 20% < 50%
        risk.validateSkew(ETH_USD, LONG, 500e18, 1_000e18, 1_000e18);
    }

    function test_RevertWhen_SkewLimitExceeded() public {
        _config(5_000, 10, 0);
        // long into empty book => 100% > 50%
        vm.expectRevert(
            abi.encodeWithSelector(RiskManager.SkewLimitExceeded.selector, ETH_USD, 10_000, 5_000)
        );
        risk.validateSkew(ETH_USD, LONG, 1_000e18, 0, 0);
    }

    function test_DeRiskingAllowedEvenAboveLimit() public {
        _config(5_000, 10, 0);
        // very long-heavy book; a short reduces imbalance => allowed despite high skew
        risk.validateSkew(ETH_USD, SHORT, 1_000e18, 5_000e18, 0);
    }

    function test_ZeroMaxSkewDisablesLimit() public {
        _config(0, 10, 0);
        risk.validateSkew(ETH_USD, LONG, 1_000_000e18, 0, 0); // no revert
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("RM: zero roles");
        new RiskManager(address(0));
    }

    // ------------------------------ fuzz ------------------------------- //

    function testFuzz_FeeNeverBelowBase(uint256 sizeDelta, uint256 longOi, uint256 shortOi) public {
        _config(0, 10, 100);
        sizeDelta = bound(sizeDelta, 1, 1_000_000e18);
        longOi = bound(longOi, 0, 1_000_000e18);
        shortOi = bound(shortOi, 0, 1_000_000e18);
        uint256 fee = risk.feeBps(ETH_USD, LONG, sizeDelta, longOi, shortOi);
        assertGe(fee, 10);
    }
}