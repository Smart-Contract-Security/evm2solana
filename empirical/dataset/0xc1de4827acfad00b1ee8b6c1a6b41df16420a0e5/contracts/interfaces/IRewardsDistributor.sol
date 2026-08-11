// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRewardsDistributor {
    function accrueReward(address vault, address rewardToken, uint256 amount) external;

    function settle(address user, address vault) external;
    function settleOne(address user, address vault, address rewardToken) external;
    function syncDebt(address user, address vault) external;

    function pending(address user, address vault, address rewardToken) external view returns (uint256);

    function claimReward(address vault, address rewardToken) external returns (uint256);
    function claimAll(address vault) external returns (uint256 totalClaimedTokens);
    function rewardTokensFor(address vault) external view returns (address[] memory);

    event RewardAccrued(address indexed vault, address indexed rewardToken, uint256 amount);
    event RewardClaimed(address indexed vault, address indexed user, address indexed rewardToken, uint256 amount);
}
