// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable}         from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/// @title DarkRewardsV2 — Synthetix-style $DARK staking pool.
///
/// Users stake $DARK and earn $DARK from a finite emission pool. At deploy,
/// 300M $DARK is parked in this contract. The owner calls notifyRewardAmount
/// to schedule the linear emission over a chosen duration (default 90 days).
///
/// Public:
///   - stake(amount)
///   - withdraw(amount)
///   - claim()
///   - exit()             — withdraw + claim in one tx
///   - earned(user)       — view pending rewards
///   - rewardPerToken()   — view current acc index
///
/// Owner-only:
///   - notifyRewardAmount(amount, duration)
///   - rescue(amount)     — emergency exit for the launch-and-abort flow
contract DarkRewardsV2 is Ownable {
    using SafeTransferLib for address;

    IERC20Min public immutable dark;

    uint256 public rewardRate;          // DARK per second
    uint256 public periodFinish;        // timestamp when streaming ends
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalStaked;
    mapping(address => uint256) public stakedOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount, uint256 duration, uint256 newRate);
    event Rescued(uint256 amount);

    constructor(address _dark, address _owner) {
        require(_dark != address(0) && _owner != address(0), "zero addr");
        dark = IERC20Min(_dark);
        _initializeOwner(_owner);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // ---- Views --------------------------------------------------------------

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        return rewardPerTokenStored
            + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return (stakedOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18
             + rewards[account];
    }

    function balanceOf(address account) external view returns (uint256) { return stakedOf[account]; }

    // ---- User actions -------------------------------------------------------

    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "zero amount");
        require(dark.transferFrom(msg.sender, address(this), amount), "pull fail");
        totalStaked += amount;
        stakedOf[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0 && amount <= stakedOf[msg.sender], "bad amount");
        totalStaked -= amount;
        stakedOf[msg.sender] -= amount;
        require(dark.transfer(msg.sender, amount), "transfer fail");
        emit Withdrawn(msg.sender, amount);
    }

    function claim() public updateReward(msg.sender) returns (uint256 owed) {
        owed = rewards[msg.sender];
        require(owed > 0, "nothing");
        rewards[msg.sender] = 0;
        require(dark.transfer(msg.sender, owed), "claim fail");
        emit Claimed(msg.sender, owed);
    }

    function exit() external {
        uint256 staked = stakedOf[msg.sender];
        if (staked > 0) {
            // Re-implement withdraw inline to avoid double-modifier overhead
            _doWithdraw(staked);
        }
        if (rewards[msg.sender] > 0) claim();
    }

    function _doWithdraw(uint256 amount) internal updateReward(msg.sender) {
        totalStaked -= amount;
        stakedOf[msg.sender] -= amount;
        require(dark.transfer(msg.sender, amount), "transfer fail");
        emit Withdrawn(msg.sender, amount);
    }

    // ---- Owner --------------------------------------------------------------

    /// @notice Schedule `amount` $DARK to stream over `duration` seconds.
    ///         The contract must already hold the rewards balance.
    function notifyRewardAmount(uint256 amount, uint256 duration)
        external onlyOwner updateReward(address(0))
    {
        require(duration > 0, "zero duration");
        require(amount > 0, "zero amount");

        if (block.timestamp >= periodFinish) {
            rewardRate = amount / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover  = remaining * rewardRate;
            rewardRate = (amount + leftover) / duration;
        }

        // Sanity: contract must hold enough DARK for the schedule
        uint256 bal = dark.balanceOf(address(this));
        require(rewardRate * duration <= bal - totalStaked, "insufficient pool");

        lastUpdateTime = block.timestamp;
        periodFinish   = block.timestamp + duration;
        emit RewardAdded(amount, duration, rewardRate);
    }

    /// @notice Emergency exit — owner pulls back DARK that is NOT staked.
    ///         Used during the launch-and-abort flow to recover the un-streamed pool.
    function rescue(uint256 amount) external onlyOwner {
        uint256 bal       = dark.balanceOf(address(this));
        uint256 available = bal - totalStaked;
        require(amount <= available, "exceeds available");
        require(dark.transfer(owner(), amount), "rescue fail");

        // Stop future emission — anything not yet earned by stakers is gone
        rewardRate    = 0;
        periodFinish  = block.timestamp;
        lastUpdateTime = block.timestamp;
        emit Rescued(amount);
    }
}
