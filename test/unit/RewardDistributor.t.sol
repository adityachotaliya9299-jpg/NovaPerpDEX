// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase6Base} from "../Phase6Base.sol";
import {RewardDistributor} from "../../src/core/RewardDistributor.sol";

/// @title RewardDistributorTest
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Tests for the accumulator-based LP share staking and reward emission.
contract RewardDistributorTest is Phase6Base {
    function _stake(address lp, uint256 amount) internal {
        vm.startPrank(lp);
        lpVault.approve(address(rewardDistributor), amount);
        rewardDistributor.stake(amount);
        vm.stopPrank();
    }

    // ----------------------------- constructor ------------------------------ //

    function test_RevertWhen_ConstructedWithZeroRoles() public {
        vm.expectRevert("RD: zero roles");
        new RewardDistributor(address(0), address(lpVault), address(rewardToken));
    }

    function test_RevertWhen_ConstructedWithZeroLpVault() public {
        vm.expectRevert("RD: zero lpv");
        new RewardDistributor(address(roles), address(0), address(rewardToken));
    }

    function test_RevertWhen_ConstructedWithZeroRewardToken() public {
        vm.expectRevert("RD: zero reward");
        new RewardDistributor(address(roles), address(lpVault), address(0));
    }

    // ----------------------------- stake / unstake ------------------------------ //

    function test_StakeMovesShares() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);

        _stake(lp1, shares);

        assertEq(lpVault.balanceOf(lp1), 0);
        assertEq(lpVault.balanceOf(address(rewardDistributor)), shares);
        assertEq(rewardDistributor.stakedOf(lp1), shares);
        assertEq(rewardDistributor.totalStaked(), shares);
    }

    function test_RevertWhen_StakeZero() public {
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        rewardDistributor.stake(0);
    }

    function test_RevertWhen_StakeMoreThanBalance() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        vm.startPrank(lp1);
        lpVault.approve(address(rewardDistributor), shares + 1);
        vm.expectRevert(
            abi.encodeWithSelector(RewardDistributor.InsufficientStake.selector, lp1, shares + 1, shares)
        );
        rewardDistributor.stake(shares + 1);
        vm.stopPrank();
    }

    function test_UnstakeReturnsShares() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        _stake(lp1, shares);

        vm.prank(lp1);
        rewardDistributor.unstake(shares);

        assertEq(lpVault.balanceOf(lp1), shares);
        assertEq(rewardDistributor.stakedOf(lp1), 0);
        assertEq(rewardDistributor.totalStaked(), 0);
    }

    function test_RevertWhen_UnstakeZero() public {
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        rewardDistributor.unstake(0);
    }

    function test_RevertWhen_UnstakeMoreThanStaked() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        _stake(lp1, shares);

        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(RewardDistributor.InsufficientStake.selector, lp1, shares + 1, shares)
        );
        rewardDistributor.unstake(shares + 1);
    }

    function test_PartialUnstake() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        _stake(lp1, shares);

        vm.prank(lp1);
        rewardDistributor.unstake(shares / 2);

        assertEq(rewardDistributor.stakedOf(lp1), shares - shares / 2);
        assertEq(rewardDistributor.totalStaked(), shares - shares / 2);
    }

    // ----------------------------- fund / rate ------------------------------ //

    function test_FundSetsRewardRate() public {
        _fundRewards(1_000e18, 1_000); // 1000 tokens over 1000 seconds = 1/sec
        assertEq(rewardDistributor.rewardRate(), 1e18);
        assertEq(rewardDistributor.unallocatedRewards(), 1_000e18);
    }

    function test_RevertWhen_FundZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        rewardDistributor.fund(0, 1_000);
    }

    function test_RevertWhen_FundZeroDuration() public {
        rewardToken.mint(admin, 1_000e18);
        vm.startPrank(admin);
        rewardToken.approve(address(rewardDistributor), 1_000e18);
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        rewardDistributor.fund(1_000e18, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_NonGovernorFunds() public {
        rewardToken.mint(alice, 1_000e18);
        vm.startPrank(alice);
        rewardToken.approve(address(rewardDistributor), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NotGovernor.selector, alice));
        rewardDistributor.fund(1_000e18, 1_000);
        vm.stopPrank();
    }

    function test_GovernorCanSetRewardRate() public {
        vm.prank(admin);
        rewardDistributor.setRewardRate(5e18);
        assertEq(rewardDistributor.rewardRate(), 5e18);
    }

    function test_RevertWhen_NonGovernorSetsRewardRate() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NotGovernor.selector, alice));
        rewardDistributor.setRewardRate(5e18);
    }

    // ----------------------------- accrual ------------------------------ //

    function test_SingleStakerEarnsFullEmission() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        _stake(lp1, shares);

        _fundRewards(1_000e18, 1_000); // 1 token/sec
        vm.warp(block.timestamp + 100);

        // Accumulator pattern: accRewardPerShare = emitted * 1e18 / totalStaked rounds
        // down, so up to 1 wei of each period's emission is dust. Standard MasterChef
        // behavior — never overpays, dust is bounded by the number of accrual events.
        assertApproxEqAbs(rewardDistributor.earned(lp1), 100e18, 1);
    }

    function test_TwoStakersSplitProportionally() public {
        _lpDeposit(lp1, 10_000e18);
        _lpDeposit(lp2, 30_000e18); // lp2 has 3x lp1's shares (both at 1:1 price)
        _stake(lp1, lpVault.balanceOf(lp1));
        _stake(lp2, lpVault.balanceOf(lp2));

        _fundRewards(1_000e18, 1_000); // 1 token/sec
        vm.warp(block.timestamp + 100); // 100 tokens emitted total

        // lp1 has 1/4 of total staked shares, lp2 has 3/4. Accumulator rounding dust
        // (see test_SingleStakerEarnsFullEmission) scales with totalStaked's odd
        // remainder here; 1e4 wei (1e-14 of a token) is negligible economically.
        assertApproxEqAbs(rewardDistributor.earned(lp1), 25e18, 1e4);
        assertApproxEqAbs(rewardDistributor.earned(lp2), 75e18, 1e4);
    }

    function test_ClaimTransfersRewardToken() public {
        _lpDeposit(lp1, 10_000e18);
        _stake(lp1, lpVault.balanceOf(lp1));
        _fundRewards(1_000e18, 1_000);
        vm.warp(block.timestamp + 100);

        vm.prank(lp1);
        uint256 claimed = rewardDistributor.claim();

        // 1 wei of accumulator-rounding dust (see test_SingleStakerEarnsFullEmission)
        assertApproxEqAbs(claimed, 100e18, 1);
        assertEq(rewardToken.balanceOf(lp1), claimed);
        assertEq(rewardDistributor.earned(lp1), 0);
    }

    function test_RevertWhen_ClaimWithNothingPending() public {
        _lpDeposit(lp1, 10_000e18);
        _stake(lp1, lpVault.balanceOf(lp1));
        vm.prank(lp1);
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        rewardDistributor.claim();
    }

    function test_EmissionCapsAtUnallocated() public {
        _lpDeposit(lp1, 10_000e18);
        _stake(lp1, lpVault.balanceOf(lp1));
        _fundRewards(100e18, 100); // 1 token/sec, 100 tokens total

        vm.warp(block.timestamp + 1_000); // far beyond the funded duration
        // capped at the funded 100e18, not 1000e18, modulo 1 wei accumulator dust
        assertApproxEqAbs(rewardDistributor.earned(lp1), 100e18, 1);
    }

    function test_LateStakerDoesNotEarnPastEmissions() public {
        _lpDeposit(lp1, 10_000e18);
        _stake(lp1, lpVault.balanceOf(lp1));
        _fundRewards(1_000e18, 1_000);
        vm.warp(block.timestamp + 100); // 100 tokens emitted, all to lp1 so far

        _lpDeposit(lp2, 10_000e18);
        _stake(lp2, lpVault.balanceOf(lp2));

        // lp2 stakes right as lp1's 100 accrue; lp2 has earned nothing yet
        assertEq(rewardDistributor.earned(lp2), 0);
        assertApproxEqAbs(rewardDistributor.earned(lp1), 100e18, 1);
    }

    function test_UnstakeSettlesPendingRewards() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        _stake(lp1, shares);
        _fundRewards(1_000e18, 1_000);
        vm.warp(block.timestamp + 100);

        vm.prank(lp1);
        rewardDistributor.unstake(shares);

        // pending rewards preserved even after fully unstaking
        assertApproxEqAbs(rewardDistributor.earned(lp1), 100e18, 1);
    }

    // ----------------------------- fuzz ------------------------------- //

    function testFuzz_EarnedNeverExceedsFunded(uint256 fundAmount, uint256 elapsed) public {
        fundAmount = bound(fundAmount, 1e18, 1_000_000e18);
        elapsed = bound(elapsed, 1, 365 days);

        _lpDeposit(lp1, 10_000e18);
        _stake(lp1, lpVault.balanceOf(lp1));
        _fundRewards(fundAmount, 1_000);

        vm.warp(block.timestamp + elapsed);
        assertLe(rewardDistributor.earned(lp1), fundAmount);
    }
}