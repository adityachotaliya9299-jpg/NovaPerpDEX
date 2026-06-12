// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase6Base} from "../Phase6Base.sol";
import {SettlementEngine} from "../../src/core/SettlementEngine.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";

/// @title SettlementEngineTest
/// @notice Tests for epoch-based fee sweeping and the LP/treasury split.
contract SettlementEngineTest is Phase6Base {
    /// @dev Opens and fully closes a position to generate real, accrued fees in
    ///      {FeeDistributor} (open fee + close fee, both `feeOnSize` at 10bps).
    function _generateFees() internal {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 2_000e18);
        vm.prank(alice);
        mm.closePosition(ETH_USD, LONG);
    }

    // ----------------------------- constructor ------------------------------ //

    function test_ConstructorSetsState() public view {
        assertEq(settlement.epochDuration(), DEFAULT_EPOCH_DURATION);
        assertEq(settlement.lpShareBps(), DEFAULT_LP_SHARE_BPS);
        assertEq(settlement.epoch(), 0);
        assertEq(settlement.settledFees(), 0);
    }

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("SE: zero roles");
        new SettlementEngine(address(0), address(fees), address(lpVault), 1 days, 5_000);
    }

    function test_RevertWhen_ConstructedWithZeroFeeDistributor() public {
        vm.expectRevert("SE: zero fd");
        new SettlementEngine(address(roles), address(0), address(lpVault), 1 days, 5_000);
    }

    function test_RevertWhen_ConstructedWithZeroLpVault() public {
        vm.expectRevert("SE: zero lpv");
        new SettlementEngine(address(roles), address(fees), address(0), 1 days, 5_000);
    }

    function test_RevertWhen_ConstructedWithLpShareTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.LpShareTooHigh.selector, 10_001));
        new SettlementEngine(address(roles), address(fees), address(lpVault), 1 days, 10_001);
    }

    // ----------------------------- pendingSettlement ------------------------------ //

    function test_PendingSettlementZeroInitially() public view {
        assertEq(settlement.pendingSettlement(), 0);
    }

    function test_PendingSettlementReflectsAccruedFees() public {
        _generateFees();
        // open fee (10bps of 10000) + close fee (10bps of 10000) = 10 + 10 = 20
        assertEq(settlement.pendingSettlement(), 20e18);
        assertEq(settlement.pendingSettlement(), fees.totalFees());
    }

    // ----------------------------- epochElapsed ------------------------------ //

    function test_EpochNotElapsedInitially() public view {
        // epochStart == now at construction, duration is 1 day
        assertFalse(settlement.epochElapsed());
    }

    function test_EpochElapsedAfterDuration() public {
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        assertTrue(settlement.epochElapsed());
    }

    // ----------------------------- settle ------------------------------ //

    function test_RevertWhen_SettleBeforeEpochElapsed() public {
        _generateFees();
        vm.expectRevert(
            abi.encodeWithSelector(
                SettlementEngine.EpochNotElapsed.selector,
                block.timestamp + DEFAULT_EPOCH_DURATION,
                block.timestamp
            )
        );
        settlement.settle();
    }

    function test_RevertWhen_SettleWithNothingToSettle() public {
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        vm.expectRevert(SettlementEngine.NothingToSettle.selector);
        settlement.settle();
    }

    function test_SettleSplitsFeesByConfiguredBps() public {
        _generateFees(); // 20e18 total fees
        _lpDeposit(lp1, 10_000e18); // LPs must exist for the LP share to route to them

        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        (uint256 amount, uint256 lpShare, uint256 treasuryShare) = settlement.settle();

        assertEq(amount, 20e18);
        assertEq(lpShare, 10e18); // 50%
        assertEq(treasuryShare, 10e18);
        assertEq(settlement.settledFees(), 20e18);
        assertEq(settlement.epoch(), 1);
    }

    function test_SettleRaisesLpSharePrice() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 priceBefore = lpVault.sharePrice();

        _generateFees();
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        settlement.settle();

        assertGt(lpVault.sharePrice(), priceBefore);
    }

    function test_SettleSendsTreasuryShareToTreasury() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 treasuryBefore = usd.balanceOf(treasury);

        _generateFees();
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        (, , uint256 treasuryShare) = settlement.settle();

        assertEq(usd.balanceOf(treasury), treasuryBefore + treasuryShare);
    }

    function test_SettleWithZeroLpShareSendsAllToTreasury() public {
        vm.prank(admin);
        settlement.setLpShareBps(0);

        _generateFees();
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        (uint256 amount, uint256 lpShare, uint256 treasuryShare) = settlement.settle();

        assertEq(lpShare, 0);
        assertEq(treasuryShare, amount);
    }

    function test_SettleWithNoLpsRoutesLpShareToTreasury() public {
        // No LP deposits => lpVault.totalSupply() == 0
        _generateFees();
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        (uint256 amount, uint256 lpShare, uint256 treasuryShare) = settlement.settle();

        assertEq(lpShare, 0); // donate() would revert on empty vault, so routed away
        assertEq(treasuryShare, amount); // entire amount to treasury instead
    }

    function test_SecondEpochSettlesOnlyNewFees() public {
        _lpDeposit(lp1, 10_000e18);
        _generateFees(); // 20e18
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        settlement.settle();

        _generateFees(); // another 20e18
        vm.warp(block.timestamp + DEFAULT_EPOCH_DURATION);
        (uint256 amount,,) = settlement.settle();

        assertEq(amount, 20e18); // only the new fees, not 40
        assertEq(settlement.epoch(), 2);
        assertEq(settlement.settledFees(), 40e18);
    }

    // ----------------------------- admin ------------------------------ //

    function test_GovernorCanSetEpochDuration() public {
        vm.prank(admin);
        settlement.setEpochDuration(2 days);
        assertEq(settlement.epochDuration(), 2 days);
    }

    function test_RevertWhen_NonGovernorSetsEpochDuration() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.NotGovernor.selector, alice));
        settlement.setEpochDuration(2 days);
    }

    function test_GovernorCanSetLpShareBps() public {
        vm.prank(admin);
        settlement.setLpShareBps(7_500);
        assertEq(settlement.lpShareBps(), 7_500);
    }

    function test_RevertWhen_NonGovernorSetsLpShareBps() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.NotGovernor.selector, alice));
        settlement.setLpShareBps(7_500);
    }

    function test_RevertWhen_SetLpShareBpsTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.LpShareTooHigh.selector, 10_001));
        settlement.setLpShareBps(10_001);
    }

    // ----------------------------- FeeDistributor.collectAndSplit ------------------------------ //

    function test_RevertWhen_CollectAndSplitNonGovernor() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.NotGovernor.selector, alice));
        fees.collectAndSplit(1e18, address(lpVault), 5_000);
    }

    function test_RevertWhen_CollectAndSplitBpsAboveDenominator() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(FeeDistributor.FeeTooHigh.selector, 10_001));
        fees.collectAndSplit(1e18, address(lpVault), 10_001);
    }
}