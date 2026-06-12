// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase6Base} from "../Phase6Base.sol";
import {LPVault} from "../../src/core/LPVault.sol";

/// @title LPVaultTest
/// @notice Unit + fuzz tests for ERC4626-style share accounting over the protocol vault.
contract LPVaultTest is Phase6Base {
    // ----------------------------- deposit ------------------------------ //

    function test_FirstDepositMintsDeadShares() public {
        uint256 shares = _lpDeposit(lp1, 10_000e18);
        assertEq(shares, 10_000e18 - lpVault.MIN_FIRST_DEPOSIT());
        assertEq(lpVault.balanceOf(address(1)), lpVault.MIN_FIRST_DEPOSIT());
        assertEq(lpVault.totalSupply(), 10_000e18);
    }

    function test_RevertWhen_FirstDepositBelowMin() public {
        usd.mint(lp1, 100);
        vm.startPrank(lp1);
        usd.approve(address(lpVault), 100);
        vm.expectRevert(
            abi.encodeWithSelector(LPVault.BelowMinFirstDeposit.selector, 100, lpVault.MIN_FIRST_DEPOSIT())
        );
        lpVault.deposit(100);
        vm.stopPrank();
    }

    function test_SecondDepositAtSamePriceMintsProportionalShares() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares2 = _lpDeposit(lp2, 5_000e18);
        // price unchanged (1:1) => shares2 == assets deposited
        assertEq(shares2, 5_000e18);
    }

    function test_RevertWhen_DepositZero() public {
        vm.expectRevert(LPVault.ZeroAmount.selector);
        lpVault.deposit(0);
    }

    // ----------------------------- withdraw ------------------------------ //

    function test_WithdrawReturnsProportionalAssets() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 lp1Shares = lpVault.balanceOf(lp1);

        vm.prank(lp1);
        uint256 assets = lpVault.withdraw(lp1Shares);

        // lp1 gets back everything except the dead-share portion (still in the vault)
        assertEq(assets, 10_000e18 - lpVault.MIN_FIRST_DEPOSIT());
        assertEq(usd.balanceOf(lp1), assets);
    }

    function test_PartialWithdraw() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 lp1Shares = lpVault.balanceOf(lp1);

        vm.prank(lp1);
        uint256 assets = lpVault.withdraw(lp1Shares / 2);

        assertEq(lpVault.balanceOf(lp1), lp1Shares - lp1Shares / 2);
        assertApproxEqAbs(assets, 5_000e18, 1);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 lp1Shares = lpVault.balanceOf(lp1);
        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(LPVault.InsufficientShares.selector, lp1, lp1Shares + 1, lp1Shares)
        );
        lpVault.withdraw(lp1Shares + 1);
    }

    function test_RevertWhen_WithdrawZero() public {
        vm.expectRevert(LPVault.ZeroAmount.selector);
        lpVault.withdraw(0);
    }

    function test_RevertWhen_WithdrawExceedsAvailableLiquidity() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 lp1Shares = lpVault.balanceOf(lp1);

        // Lock most of the LPVault's vault balance (simulating reserved trader losses)
        // by impersonating the CollateralVault, which holds OPERATOR_ROLE.
        vm.prank(address(cvault));
        vault.lock(address(lpVault), 9_000e18);

        uint256 available = lpVault.availableLiquidity();
        uint256 wantAssets = lpVault.previewRedeem(lp1Shares);
        assertGt(wantAssets, available);

        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(LPVault.InsufficientLiquidity.selector, wantAssets, available)
        );
        lpVault.withdraw(lp1Shares);
    }

    // ----------------------------- share price ------------------------------ //

    function test_SharePriceOneBeforeAnyDeposit() public view {
        assertEq(lpVault.sharePrice(), 1e18);
    }

    function test_SharePriceOneAfterFirstDeposit() public {
        _lpDeposit(lp1, 10_000e18);
        assertEq(lpVault.sharePrice(), 1e18);
    }

    function test_DonateRaisesSharePrice() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 priceBefore = lpVault.sharePrice();

        usd.mint(lp2, 1_000e18);
        vm.startPrank(lp2);
        usd.approve(address(lpVault), 1_000e18);
        lpVault.donate(1_000e18);
        vm.stopPrank();

        uint256 priceAfter = lpVault.sharePrice();
        assertGt(priceAfter, priceBefore);
        // totalSupply unchanged, totalAssets +1000 => price up by 1000/10000 = 10%
        assertApproxEqAbs(priceAfter, priceBefore + priceBefore / 10, 2);
    }

    function test_DonateBenefitsExistingLPsProportionally() public {
        _lpDeposit(lp1, 10_000e18);
        _lpDeposit(lp2, 10_000e18);

        usd.mint(address(this), 2_000e18);
        usd.approve(address(lpVault), 2_000e18);
        lpVault.donate(2_000e18);

        // both LPs' shares are now worth more
        uint256 lp1Assets = lpVault.previewRedeem(lpVault.balanceOf(lp1));
        uint256 lp2Assets = lpVault.previewRedeem(lpVault.balanceOf(lp2));
        assertGt(lp1Assets, 10_000e18);
        assertGt(lp2Assets, 10_000e18);
        assertApproxEqAbs(lp1Assets, lp2Assets, 2);
    }

    function test_RevertWhen_DonateZero() public {
        _lpDeposit(lp1, 10_000e18);
        vm.expectRevert(LPVault.ZeroAmount.selector);
        lpVault.donate(0);
    }

    function test_RevertWhen_DonateBeforeAnyDeposit() public {
        usd.mint(address(this), 1_000e18);
        usd.approve(address(lpVault), 1_000e18);
        vm.expectRevert(LPVault.ZeroAmount.selector);
        lpVault.donate(1_000e18);
    }

    // ----------------------------- transfer/approve ------------------------------ //

    function test_TransferMovesShares() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        vm.prank(lp1);
        lpVault.transfer(lp2, shares);
        assertEq(lpVault.balanceOf(lp1), 0);
        assertEq(lpVault.balanceOf(lp2), shares);
    }

    function test_ApproveAndTransferFrom() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        vm.prank(lp1);
        lpVault.approve(address(this), shares);
        lpVault.transferFrom(lp1, lp2, shares);
        assertEq(lpVault.balanceOf(lp2), shares);
        assertEq(lpVault.allowance(lp1, address(this)), 0);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        vm.prank(lp1);
        lpVault.approve(address(this), shares - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LPVault.InsufficientAllowance.selector, lp1, address(this), shares, shares - 1
            )
        );
        lpVault.transferFrom(lp1, lp2, shares);
    }

    function test_InfiniteApprovalNotDecremented() public {
        _lpDeposit(lp1, 10_000e18);
        uint256 shares = lpVault.balanceOf(lp1);
        vm.prank(lp1);
        lpVault.approve(address(this), type(uint256).max);
        lpVault.transferFrom(lp1, lp2, shares);
        assertEq(lpVault.allowance(lp1, address(this)), type(uint256).max);
    }

    // ----------------------------- constructor ------------------------------ //

    function test_RevertWhen_ConstructedWithZeroAsset() public {
        vm.expectRevert("LPV: zero asset");
        new LPVault(address(0), address(vault));
    }

    function test_RevertWhen_ConstructedWithZeroVault() public {
        vm.expectRevert("LPV: zero vault");
        new LPVault(address(usd), address(0));
    }

    // ----------------------------- totalAssets ------------------------------ //

    function test_TotalAssetsTracksVaultBalance() public {
        _lpDeposit(lp1, 10_000e18);
        assertEq(lpVault.totalAssets(), vault.totalOf(address(lpVault)));
        assertEq(lpVault.totalAssets(), 10_000e18);
    }

    // ----------------------------- fuzz ------------------------------- //

    function testFuzz_DepositWithdrawRoundTrip(uint256 amount) public {
        amount = bound(amount, lpVault.MIN_FIRST_DEPOSIT() + 1, 1_000_000e18);
        uint256 shares = _lpDeposit(lp1, amount);
        vm.prank(lp1);
        uint256 assetsBack = lpVault.withdraw(shares);
        // first depositor loses exactly the dead-share portion
        assertEq(assetsBack, amount - lpVault.MIN_FIRST_DEPOSIT());
    }

    function testFuzz_SharePriceNeverDecreasesFromDonation(uint256 deposit_, uint256 donation) public {
        deposit_ = bound(deposit_, lpVault.MIN_FIRST_DEPOSIT() + 1, 1_000_000e18);
        donation = bound(donation, 1, 1_000_000e18);
        _lpDeposit(lp1, deposit_);
        uint256 before = lpVault.sharePrice();

        usd.mint(address(this), donation);
        usd.approve(address(lpVault), donation);
        lpVault.donate(donation);

        assertGe(lpVault.sharePrice(), before);
    }
}