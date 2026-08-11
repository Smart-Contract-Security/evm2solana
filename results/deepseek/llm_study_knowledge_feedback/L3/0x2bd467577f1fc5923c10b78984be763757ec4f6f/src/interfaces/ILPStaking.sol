// SPDX-License-Identifier: MIT

import 'solana';

interface ILPStaking {
    function setInitializer(
        address _initializer
    ) external;
    function initialize(
        address lpToken,
        address rewardToken,
        address feeDistributor,
        uint64 seedTime,
        uint64 vestingAllocation
    ) external;
    function stake(
        uint64 amount
    ) external;
    function withdraw(
        uint64 amount
    ) external;
    function claim() external returns (uint64 amount);
    function notifyFees(
        uint64 amount
    ) external;
    function pendingRewards(
        address account
    ) external view returns (uint64);
    function getPoolStats()
        external
        view
        returns (
            uint64 totalLpStaked,
            uint64 totalWeight,
            uint64 vestingPerSecond,
            uint64 vestingRemaining,
            uint64 currentEpochFees,
            uint64 feeRewardRate,
            uint64 pendingEpochFees,
            uint64 epochTimeRemaining
        );
    function getUserInfo(
        address account
    )
        external
        view
        returns (uint64 stakedLp, uint64 currentMp, uint64 effectiveWeight, uint64 pending, uint64 poolShareBps);
}