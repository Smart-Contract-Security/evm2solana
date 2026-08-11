// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IBoostHub {
    struct PoolView {
        address asset;
        address gauge;
        bool active;
        bool shutdown;
        uint256 totalStaked;
        address[] rewardTokens;
    }

    function deposit(uint256 pid, uint256 amount) external;
    function withdraw(uint256 pid, uint256 amount, address receiver) external;
    function harvest(uint256 pid) external returns (address[] memory tokens, uint256[] memory amounts);
    function claim(uint256 pid, address receiver) external returns (address[] memory tokens, uint256[] memory amounts);
    function claimReward(uint256 pid, address rewardToken, address receiver) external returns (uint256 amount);
    function balanceOf(uint256 pid, address strategy) external view returns (uint256);
    function pendingRewards(uint256 pid, address strategy)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);
    function poolInfo(uint256 pid) external view returns (PoolView memory);
}
