// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Garrison is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidTier();
    error StillLocked();
    error NothingStaked();
    error NotHook();
    error HookAlreadySet();
    error ZeroAmount();

    struct Position {
        uint128 amount;
        uint64 unlockAt;
        uint256 rewardDebt;
    }

    IERC20 public immutable fort;
    address public hook;

    uint64[3] public TIER_LOCKS = [uint64(1 days), uint64(7 days), uint64(30 days)];
    uint8[3]  public TIER_MULTIPLIERS = [1, 2, 5];

    mapping(address => Position[3]) public positions;
    uint256 public totalEffectiveShares;
    uint256 public rewardPerShareCumulative;
    uint256 public pendingRewards;

    uint256 private constant ACC_SCALE = 1e18;

    event Staked(address indexed user, uint8 tier, uint256 amount, uint64 unlockAt);
    event Unstaked(address indexed user, uint8 tier, uint256 amount, uint256 ethClaimed);
    event Claimed(address indexed user, uint8 tier, uint256 ethClaimed);
    event RewardNotified(uint256 ethAmount, uint256 totalShares);
    event HookSet(address hook);

    constructor(address fort_, address owner_) Ownable(owner_) {
        fort = IERC20(fort_);
    }

    function setHook(address hook_) external onlyOwner {
        if (hook != address(0)) revert HookAlreadySet();
        hook = hook_;
        emit HookSet(hook_);
    }

    function _multiplier(uint8 tier) internal view returns (uint256) {
        if (tier > 2) revert InvalidTier();
        return TIER_MULTIPLIERS[tier];
    }

    function _pendingFor(Position storage p, uint256 mult) internal view returns (uint256) {
        uint256 effShares = uint256(p.amount) * mult;
        uint256 cumulative = (effShares * rewardPerShareCumulative) / ACC_SCALE;
        return cumulative - p.rewardDebt;
    }

    function stake(uint8 tier, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 mult = _multiplier(tier);
        Position storage p = positions[msg.sender][tier];

        if (p.amount > 0) {
            uint256 owed = _pendingFor(p, mult);
            if (owed > 0) {
                (bool ok, ) = msg.sender.call{value: owed}("");
                require(ok, "eth send failed");
                emit Claimed(msg.sender, tier, owed);
            }
        }

        p.amount += uint128(amount);
        p.unlockAt = uint64(block.timestamp + TIER_LOCKS[tier]);
        totalEffectiveShares += amount * mult;
        p.rewardDebt = (uint256(p.amount) * mult * rewardPerShareCumulative) / ACC_SCALE;

        fort.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, tier, amount, p.unlockAt);
    }

    function unstake(uint8 tier) external nonReentrant {
        uint256 mult = _multiplier(tier);
        Position storage p = positions[msg.sender][tier];
        if (p.amount == 0) revert NothingStaked();
        if (block.timestamp < p.unlockAt) revert StillLocked();

        uint256 owed = _pendingFor(p, mult);
        uint256 amount = p.amount;
        totalEffectiveShares -= amount * mult;
        p.amount = 0;
        p.unlockAt = 0;
        p.rewardDebt = 0;

        fort.safeTransfer(msg.sender, amount);
        if (owed > 0) {
            (bool ok, ) = msg.sender.call{value: owed}("");
            require(ok, "eth send failed");
        }
        emit Unstaked(msg.sender, tier, amount, owed);
    }

    function claim(uint8 tier) external nonReentrant {
        uint256 mult = _multiplier(tier);
        Position storage p = positions[msg.sender][tier];
        if (p.amount == 0) revert NothingStaked();
        uint256 owed = _pendingFor(p, mult);
        p.rewardDebt = (uint256(p.amount) * mult * rewardPerShareCumulative) / ACC_SCALE;
        if (owed > 0) {
            (bool ok, ) = msg.sender.call{value: owed}("");
            require(ok, "eth send failed");
            emit Claimed(msg.sender, tier, owed);
        }
    }

    function pending(address user, uint8 tier) external view returns (uint256) {
        if (tier > 2) revert InvalidTier();
        Position storage p = positions[user][tier];
        if (p.amount == 0) return 0;
        return _pendingFor(p, TIER_MULTIPLIERS[tier]);
    }

    function notifyReward() external payable {
        if (msg.sender != hook) revert NotHook();
        if (msg.value == 0) return;
        if (totalEffectiveShares == 0) {
            pendingRewards += msg.value;
            return;
        }
        uint256 total = msg.value + pendingRewards;
        pendingRewards = 0;
        rewardPerShareCumulative += (total * ACC_SCALE) / totalEffectiveShares;
        emit RewardNotified(total, totalEffectiveShares);
    }

    receive() external payable {}
}
