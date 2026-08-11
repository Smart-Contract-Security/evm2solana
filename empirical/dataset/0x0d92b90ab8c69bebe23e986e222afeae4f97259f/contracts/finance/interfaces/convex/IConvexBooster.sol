// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Convex Booster on Ethereum mainnet (and other non-L2 deployments).
interface IConvexBooster {
  function deposit(uint256 pid, uint256 amount, bool stake) external returns (bool);

  function withdraw(uint256 pid, uint256 amount) external returns (bool);

  function earmarkRewards(uint256 pid) external;

  function poolLength() external view returns (uint256);

  function poolInfo(uint256 pid)
    external
    view
    returns (
      address lptoken,
      address token,
      address gauge,
      address crvRewards,
      address stash,
      bool shutdown
    );
}
