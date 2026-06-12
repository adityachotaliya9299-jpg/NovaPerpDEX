// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RoleManager} from "./RoleManager.sol";
import {FeeDistributor} from "./FeeDistributor.sol";

/// @title SettlementEngine
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Epoch-based policy layer over {FeeDistributor.collectAndSplit}: tracks how
///         much of `totalFees` has been settled, and periodically sweeps the unsettled
///         delta to LPs and treasury by a governor-set split.
/// @dev This contract must itself hold GOVERNOR_ROLE in {RoleManager} to call
///      `collectAndSplit` — a standard, auditable permission grant (the same shape as
///      granting OPERATOR_ROLE to the margin engine). It holds no funds of its own;
///      `settle()` is a pure pass-through that also advances the epoch bookkeeping.
contract SettlementEngine {
    RoleManager public immutable roles;
    FeeDistributor public immutable feeDistributor;
    address public immutable lpVault;

    /// @notice Minimum time between epochs, in seconds.
    uint256 public epochDuration;

    /// @notice Timestamp at which the current epoch began.
    uint256 public epochStart;

    /// @notice Current epoch number (incremented by each {settle} call).
    uint256 public epoch;

    /// @notice Cumulative fees already swept in prior epochs.
    uint256 public settledFees;

    /// @notice Share of each epoch's fees routed to LPs, in basis points.
    uint256 public lpShareBps;

    event Settled(
        uint256 indexed epoch, uint256 amount, uint256 lpShare, uint256 treasuryShare, uint256 timestamp
    );
    event EpochDurationSet(uint256 duration);
    event LpShareSet(uint256 bps);

    error NotGovernor(address caller);
    error EpochNotElapsed(uint256 readyAt, uint256 now_);
    error NothingToSettle();
    error LpShareTooHigh(uint256 bps);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    /// @param roleManager Shared RoleManager.
    /// @param feeDistributor_ The FeeDistributor to settle from.
    /// @param lpVault_ The LPVault to receive the LP share via `donate`.
    /// @param epochDuration_ Minimum seconds between settlements.
    /// @param lpShareBps_ Initial LP share of each epoch's fees, in bps (0-10000).
    constructor(
        address roleManager,
        address feeDistributor_,
        address lpVault_,
        uint256 epochDuration_,
        uint256 lpShareBps_
    ) {
        require(roleManager != address(0), "SE: zero roles");
        require(feeDistributor_ != address(0), "SE: zero fd");
        require(lpVault_ != address(0), "SE: zero lpv");
        if (lpShareBps_ > 10_000) revert LpShareTooHigh(lpShareBps_);
        roles = RoleManager(roleManager);
        feeDistributor = FeeDistributor(feeDistributor_);
        lpVault = lpVault_;
        epochDuration = epochDuration_;
        lpShareBps = lpShareBps_;
        epochStart = block.timestamp;
    }

    /// @notice Total fees accrued by the FeeDistributor that haven't been settled yet.
    function pendingSettlement() public view returns (uint256) {
        uint256 total = feeDistributor.totalFees();
        return total > settledFees ? total - settledFees : 0;
    }

    /// @notice Whether enough time has passed since `epochStart` to call {settle}.
    function epochElapsed() public view returns (bool) {
        return block.timestamp >= epochStart + epochDuration;
    }

    /// @notice Sweeps all unsettled fees, splits them per {lpShareBps}, and advances
    ///         the epoch. Reverts if the epoch duration hasn't elapsed or there is
    ///         nothing to settle.
    function settle() external returns (uint256 amount, uint256 lpShare, uint256 treasuryShare) {
        if (!epochElapsed()) revert EpochNotElapsed(epochStart + epochDuration, block.timestamp);
        amount = pendingSettlement();
        if (amount == 0) revert NothingToSettle();

        settledFees += amount;
        epoch += 1;
        epochStart = block.timestamp;

        (lpShare, treasuryShare) = feeDistributor.collectAndSplit(amount, lpVault, lpShareBps);

        emit Settled(epoch, amount, lpShare, treasuryShare, block.timestamp);
    }

    /// @notice Updates the minimum seconds between epochs. Governor-only.
    function setEpochDuration(uint256 duration) external onlyGovernor {
        epochDuration = duration;
        emit EpochDurationSet(duration);
    }

    /// @notice Updates the LP share of future epochs' fees, in bps. Governor-only.
    function setLpShareBps(uint256 bps) external onlyGovernor {
        if (bps > 10_000) revert LpShareTooHigh(bps);
        lpShareBps = bps;
        emit LpShareSet(bps);
    }
}