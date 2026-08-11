// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IConvexRewardPool {
  function balanceOf(address account) external view returns (uint256);

  function earned(address account) external view returns (uint256);

  function claimable_reward(address _token, address _account) external view returns (uint256);

  function periodFinish() external view returns (uint256);

  function getReward() external;

  function getReward(address _account, bool _claimExtras) external;

  function getReward(address _account) external;

  function withdrawAndUnwrap(uint256 _amount, bool claim) external;

  function withdrawAllAndUnwrap(bool claim) external;

  // L2 interface
  function withdraw(uint256 _amount, bool _claim) external;

  function emergencyWithdraw(uint256 _amount) external;
}
