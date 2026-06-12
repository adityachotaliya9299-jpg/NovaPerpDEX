// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RoleManager} from "./RoleManager.sol";
import {LPVault} from "./LPVault.sol";

/// @title RewardDistributor
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Stake {LPVault} shares to earn emissions of a separate reward token, via the
///         standard accumulated-rewards-per-share ("MasterChef") pattern.
/// @dev Staking pulls LPVault shares via `transferFrom` (the staker must `approve`
///      this contract first) and holds them in its own `balanceOf` until unstaked.
///      Reward tokens are funded by the governor via {fund} and distributed linearly
///      over time at {rewardRate} tokens/second, capped at the funded balance.
contract RewardDistributor {
    using SafeERC20 for IERC20;

    /// @notice Precision factor for the accumulator (matches WAD).
    uint256 private constant ACC_PRECISION = 1e18;

    RoleManager public immutable roles;
    LPVault public immutable lpVault;
    IERC20 public immutable rewardToken;

    /// @notice Reward tokens emitted per second, shared across all stakers.
    uint256 public rewardRate;

    /// @notice Reward tokens funded but not yet emitted (decreases as time passes).
    uint256 public unallocatedRewards;

    /// @notice Timestamp of the last accumulator update.
    uint256 public lastUpdateTime;

    /// @notice Accumulated rewards per share, scaled by {ACC_PRECISION}.
    uint256 public accRewardPerShare;

    /// @notice Total LPVault shares currently staked.
    uint256 public totalStaked;

    /// @notice Staked share balance per account.
    mapping(address => uint256) public stakedOf;

    /// @notice Snapshot of `accRewardPerShare` at the account's last interaction.
    mapping(address => uint256) public rewardDebt;

    /// @notice Rewards earned but not yet claimed (after the last accumulator update).
    mapping(address => uint256) public pendingRewards;

    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event Funded(uint256 amount, uint256 newRate, uint256 duration);
    event RewardRateSet(uint256 rate);

    error ZeroAmount();
    error InsufficientStake(address account, uint256 requested, uint256 available);
    error NotGovernor(address caller);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roleManager, address lpVault_, address rewardToken_) {
        require(roleManager != address(0), "RD: zero roles");
        require(lpVault_ != address(0), "RD: zero lpv");
        require(rewardToken_ != address(0), "RD: zero reward");
        roles = RoleManager(roleManager);
        lpVault = LPVault(lpVault_);
        rewardToken = IERC20(rewardToken_);
        lastUpdateTime = block.timestamp;
    }

    /// @dev Brings the accumulator up to the current time, capping emission at
    ///      `unallocatedRewards` so the contract never promises more than it holds.
    function _updateAccumulator() private {
        if (block.timestamp <= lastUpdateTime) return;
        uint256 elapsed = block.timestamp - lastUpdateTime;
        lastUpdateTime = block.timestamp;

        if (totalStaked == 0 || rewardRate == 0) return;

        uint256 emitted = elapsed * rewardRate;
        if (emitted > unallocatedRewards) emitted = unallocatedRewards;
        if (emitted == 0) return;

        unallocatedRewards -= emitted;
        accRewardPerShare += (emitted * ACC_PRECISION) / totalStaked;
    }

    /// @dev Settles `account`'s pending rewards up to the current accumulator value.
    function _settle(address account) private {
        uint256 staked = stakedOf[account];
        if (staked > 0) {
            uint256 accrued = (staked * accRewardPerShare) / ACC_PRECISION;
            pendingRewards[account] += accrued - rewardDebt[account];
        }
        rewardDebt[account] = (staked * accRewardPerShare) / ACC_PRECISION;
    }

    /// @notice Stakes `amount` of LPVault shares to start earning rewards.
    function stake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _updateAccumulator();
        _settle(msg.sender);

        uint256 bal = lpVault.balanceOf(msg.sender);
        if (amount > bal) revert InsufficientStake(msg.sender, amount, bal);
        lpVault.transferFrom(msg.sender, address(this), amount);

        stakedOf[msg.sender] += amount;
        totalStaked += amount;
        rewardDebt[msg.sender] = (stakedOf[msg.sender] * accRewardPerShare) / ACC_PRECISION;

        emit Staked(msg.sender, amount);
    }

    /// @notice Unstakes `amount` of LPVault shares, settling any pending rewards first.
    function unstake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 staked = stakedOf[msg.sender];
        if (amount > staked) revert InsufficientStake(msg.sender, amount, staked);

        _updateAccumulator();
        _settle(msg.sender);

        stakedOf[msg.sender] = staked - amount;
        totalStaked -= amount;
        rewardDebt[msg.sender] = (stakedOf[msg.sender] * accRewardPerShare) / ACC_PRECISION;
        lpVault.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /// @notice Claims all pending reward tokens for the caller.
    function claim() external returns (uint256 amount) {
        _updateAccumulator();
        _settle(msg.sender);

        amount = pendingRewards[msg.sender];
        if (amount == 0) revert ZeroAmount();
        pendingRewards[msg.sender] = 0;

        rewardToken.safeTransfer(msg.sender, amount);
        emit RewardClaimed(msg.sender, amount);
    }

    /// @notice View of an account's currently-claimable rewards.
    function earned(address account) external view returns (uint256) {
        uint256 acc = accRewardPerShare;
        if (totalStaked > 0 && rewardRate > 0 && block.timestamp > lastUpdateTime) {
            uint256 elapsed = block.timestamp - lastUpdateTime;
            uint256 emitted = elapsed * rewardRate;
            if (emitted > unallocatedRewards) emitted = unallocatedRewards;
            acc += (emitted * ACC_PRECISION) / totalStaked;
        }
        uint256 staked = stakedOf[account];
        uint256 accrued = (staked * acc) / ACC_PRECISION;
        return pendingRewards[account] + accrued - rewardDebt[account];
    }

    /// @notice Funds the distributor with `amount` of reward tokens and sets the
    ///         emission rate so the (new) balance distributes over `duration` seconds.
    /// @dev Pulls `amount` from the caller via `transferFrom`. Settles the accumulator
    ///      first so the old rate applies up to now, then recomputes the rate from the
    ///      combined remaining + newly-funded balance.
    function fund(uint256 amount, uint256 duration) external onlyGovernor {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroAmount();
        _updateAccumulator();

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        unallocatedRewards += amount;
        rewardRate = unallocatedRewards / duration;

        emit Funded(amount, rewardRate, duration);
    }

    /// @notice Directly sets the emission rate (e.g. to pause emissions with rate=0).
    ///         Governor-only. Settles the accumulator at the old rate first.
    function setRewardRate(uint256 rate) external onlyGovernor {
        _updateAccumulator();
        rewardRate = rate;
        emit RewardRateSet(rate);
    }
}