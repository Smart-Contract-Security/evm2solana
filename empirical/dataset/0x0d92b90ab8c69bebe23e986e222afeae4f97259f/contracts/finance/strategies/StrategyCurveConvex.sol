// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../OperoseStrategy.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/convex/IConvexBooster.sol";
import "../interfaces/convex/IConvexRewardPool.sol";
import "../interfaces/curve/IRewardsGauge.sol";

/**
 * @title StrategyCurveConvex
 * @notice Curve strategy switchable between Curve gauge and Convex reward pool (Ethereum mainnet).
 * @dev When pid == NO_PID, uses Curve gauge only. Otherwise stakes via Convex Booster with auto-stake.
 */
contract StrategyCurveConvex is OperoseStrategy {
  using SafeERC20 for IERC20;

  uint256 public constant NO_PID = 42069;

  IConvexBooster public booster;
  IMinter public minter;

  address public gauge;
  address public rewardPool;
  uint256 public poolId;

  bool public isCrvMintable;
  bool public isCurveRewardsClaimable;
  bool public skipEarmarkRewards;

  error InvalidLiquidityPool();

  function initialize(
    address _vault,
    address _defiToken,
    address[] memory _rewardTokens,
    address _booster,
    address _gauge,
    uint256 _pid,
    address _minter
  ) external initializer {
    _initialize(_vault, _defiToken);
    rewardTokens = _rewardTokens;
    booster = IConvexBooster(_booster);
    gauge = _gauge;
    poolId = _pid;
    minter = IMinter(_minter);
    isCurveRewardsClaimable = true;

    if (_pid != NO_PID) {
      (address lptoken,,, address crvRewards,,) = booster.poolInfo(_pid);
      if (lptoken != _defiToken) revert InvalidLiquidityPool();
      rewardPool = crvRewards;
      SafeERC20.forceApprove(IERC20(defiToken), address(booster), type(uint256).max);
    } else {
      rewardPool = address(0);
      isCrvMintable = true;
      if (gauge != address(0)) {
        SafeERC20.forceApprove(IERC20(defiToken), gauge, type(uint256).max);
      }
    }
  }

  function name() public pure override returns (string memory) {
    return "StrategyCurveConvex";
  }

  function version() public pure override returns (string memory) {
    return "1.0";
  }

  function getTvl() public view override returns (uint256 tvl) {
    if (rewardPool != address(0)) {
      return IERC20(rewardPool).totalSupply();
    }
    return IERC20(defiToken).totalSupply();
  }

  function getBalance() public view override returns (uint256 balance) {
    if (rewardPool != address(0)) {
      balance = IConvexRewardPool(rewardPool).balanceOf(address(this));
    } else if (gauge != address(0)) {
      balance = IRewardsGauge(gauge).balanceOf(address(this));
    }
  }

  function _deposit(uint256 defiAmount) private {
    if (defiAmount == 0) return;
    if (rewardPool != address(0)) {
      booster.deposit(poolId, defiAmount, true);
    } else if (gauge != address(0)) {
      IRewardsGauge(gauge).deposit(defiAmount);
    }
  }

  function deposit(uint256 defiAmount) external override onlyVault {
    _deposit(defiAmount);
  }

  function _withdraw(uint256 defiAmount) private {
    if (defiAmount == 0) return;
    if (rewardPool != address(0)) {
      IConvexRewardPool(rewardPool).withdrawAndUnwrap(defiAmount, false);
    } else if (gauge != address(0)) {
      IRewardsGauge(gauge).withdraw(defiAmount);
    }
  }

  function withdraw(uint256 defiAmount) external override onlyVault {
    if (defiAmount > 0) {
      _withdraw(defiAmount);
      IERC20(defiToken).safeTransfer(vault, defiAmount);
    }
  }

  function getClaimable(address token) public view override returns (uint256 amount) {
    if (rewardPool != address(0)) {
      try IConvexRewardPool(rewardPool).claimable_reward(token, address(this)) returns (uint256 claimable) {
        amount = claimable;
      } catch { }
    } else if (gauge != address(0)) {
      try IRewardsGauge(gauge).claimable_reward(address(this), token) returns (uint256 claimable) {
        amount = claimable;
      } catch { }
    }
  }

  function claimRewards() public override {
    if (rewardPool != address(0)) {
      if (!skipEarmarkRewards) {
        try IConvexRewardPool(rewardPool).periodFinish() returns (uint256 finish) {
          if (finish < block.timestamp) booster.earmarkRewards(poolId);
        } catch { }
      }
      IConvexRewardPool(rewardPool).getReward(address(this), true);
    } else if (gauge != address(0)) {
      if (isCrvMintable && address(minter) != address(0)) {
        minter.mint(gauge);
      }
      if (isCurveRewardsClaimable) {
        IRewardsGauge(gauge).claim_rewards(address(this));
      }
    }
  }

  function useConvex(uint256 _pid, bool claim) external onlyOwner {
    if (claim) claimRewards();
    _withdraw(getBalance());

    if (_pid != NO_PID) {
      (address lptoken,,, address crvRewards,,) = booster.poolInfo(_pid);
      if (lptoken != defiToken) revert InvalidLiquidityPool();
      rewardPool = crvRewards;
      SafeERC20.forceApprove(IERC20(defiToken), address(booster), type(uint256).max);
    } else {
      rewardPool = address(0);
    }
    poolId = _pid;

    _deposit(IERC20(defiToken).balanceOf(address(this)));
  }

  function useCurve(address _gauge, bool claim) external onlyOwner {
    if (claim) claimRewards();
    _withdraw(getBalance());

    gauge = _gauge;
    rewardPool = address(0);
    poolId = NO_PID;
    isCrvMintable = true;
    isCurveRewardsClaimable = true;

    if (gauge != address(0)) {
      SafeERC20.forceApprove(IERC20(defiToken), gauge, type(uint256).max);
    }

    _deposit(IERC20(defiToken).balanceOf(address(this)));
  }

  function setCrvMintable(bool enabled) external onlyOwner {
    isCrvMintable = enabled;
  }

  function setCurveRewardsClaimable(bool enabled) external onlyOwner {
    isCurveRewardsClaimable = enabled;
  }

  function setSkipEarmarkRewards(bool enabled) external onlyOwner {
    skipEarmarkRewards = enabled;
  }
}
