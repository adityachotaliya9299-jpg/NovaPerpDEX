// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase5Base} from "./Phase5Base.sol";
import {LPVault} from "../src/core/LPVault.sol";
import {SettlementEngine} from "../src/core/SettlementEngine.sol";
import {RewardDistributor} from "../src/core/RewardDistributor.sol";
import {EmergencyController} from "../src/core/EmergencyController.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @title Phase6Base
/// @notice Extends the Phase 5 stack with the LP vault, epoch settlement, reward
///         staking and the protocol-wide emergency pause.
/// @dev Deliberately does NOT change `CollateralVault.liquidityPool` (still the plain
///      `pool` address from {Phase2Base}) — every prior-phase test keeps settling
///      against that address exactly as before. {LPVault} is deployed and tested as
///      an independent depositor into the same underlying {Vault}, which is all its
///      mechanics require. Tests that want to demonstrate LPVault-as-liquidityPool
///      integration call `cvault.setLiquidityPool(address(lpVault))` locally.
contract Phase6Base is Phase5Base {
    LPVault internal lpVault;
    SettlementEngine internal settlement;
    RewardDistributor internal rewardDistributor;
    EmergencyController internal emergency;
    MockERC20 internal rewardToken;

    address internal lp1 = makeAddr("lp1");
    address internal lp2 = makeAddr("lp2");

    uint256 internal constant DEFAULT_EPOCH_DURATION = 1 days;
    uint256 internal constant DEFAULT_LP_SHARE_BPS = 5_000; // 50%

    function setUp() public virtual override {
        super.setUp();

        lpVault = new LPVault(address(usd), address(vault));
        rewardToken = new MockERC20("Reward", "RWD", 18);

        vm.startPrank(admin);
        settlement = new SettlementEngine(
            address(roles), address(fees), address(lpVault), DEFAULT_EPOCH_DURATION, DEFAULT_LP_SHARE_BPS
        );
        // SettlementEngine calls FeeDistributor.collectAndSplit, which is governor-gated.
        roles.grantRole(roles.GOVERNOR_ROLE(), address(settlement));

        rewardDistributor = new RewardDistributor(address(roles), address(lpVault), address(rewardToken));

        emergency = new EmergencyController(address(roles));
        mm.setEmergencyController(address(emergency));
        vm.stopPrank();
    }

    /// @notice Mints `amount` USD to `lp`, approves the LPVault, and deposits.
    function _lpDeposit(address lp, uint256 amount) internal returns (uint256 shares) {
        usd.mint(lp, amount);
        vm.startPrank(lp);
        usd.approve(address(lpVault), amount);
        shares = lpVault.deposit(amount);
        vm.stopPrank();
    }

    /// @notice Funds the RewardDistributor with `amount` reward tokens over `duration`.
    function _fundRewards(uint256 amount, uint256 duration) internal {
        rewardToken.mint(admin, amount);
        vm.startPrank(admin);
        rewardToken.approve(address(rewardDistributor), amount);
        rewardDistributor.fund(amount, duration);
        vm.stopPrank();
    }
}