// SPDX-License-Identifier: MIT

pragma solidity =0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

/**
 * @title Token Staking
 * @dev BEP20 compatible token.
 */
contract SimpleStaking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 lockedTimestamp;
        uint256 unbondTimestamp;
        uint256 rewardTimestamp;
        bool isLocked;
    }

    struct PoolInfo {
        uint256 poolShare;
        uint256 rewardTimestamp;
        uint256 tokenPerShare;
        uint256 tokenRealStaked;
        uint256 tokenReceived;
        uint256 tokenRewarded;
        uint256 tokenTotalLimit;
        uint256 lockupTimerange;
        uint256 unbondTimerange;
    }

    IERC20 public baseToken;
    IERC20 public extrToken;

    uint256 public tokenPerSecond;
    uint256 public startTimestamp;
    uint256 public closeTimestamp;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalPoolShare;
    uint256 public maxPid;

    event Deposited(address indexed user, uint256 pid, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, uint256 pid, address indexed token, uint256 amount);
    event WithdrawnReward(address indexed user, uint256 pid, address indexed token, uint256 amount);
    event WithdrawnRemain(address indexed user, uint256 pid, address indexed token, uint256 amount);
    event LockChanged(address indexed user, uint256 pid, uint256 unlock, uint256 unbond);
    event RewardChanged(address indexed token, uint256 reward);
    event StartTimestampChanged(uint256 timestamp);
    event CloseTimestampChanged(uint256 timestamp);

    constructor(uint256 lockupTimer, uint256 unbondTimer, uint256 poolLimit) {
        addPool(1, lockupTimer, unbondTimer, poolLimit);
    }

    function setTokenAddress(IERC20 _baseToken, IERC20 _extrToken) public onlyOwner {
        require(address(_baseToken) != address(0), 'Staking: token address needs to be different than zero!');
        require(address(_extrToken) != address(0), 'Staking: token address needs to be different than zero!');
        require(address(baseToken) == address(0) && address(extrToken) == address(0), 'Staking: tokens already set!');
        baseToken = _baseToken;
        extrToken = _extrToken;
    }

    function setTokenPerSecond(uint256 _tokenPerSecond) public onlyOwner {
        require(_tokenPerSecond > 0, 'Staking: amount of tokens per second should be greater than 0!');
        for (uint256 i=0; i<maxPid; i++) {
            updatePool(i);
        }
        tokenPerSecond = _tokenPerSecond;
        emit RewardChanged(address(extrToken), tokenPerSecond);
    }

    function setStartTimestamp(uint256 _startTimestamp) public onlyOwner {
        require(startTimestamp == 0, 'Staking: start timestamp already set');
        require(_startTimestamp > 0, 'Staking: start timestamp needs to be higher than zero!');
        startTimestamp = _startTimestamp;
        emit StartTimestampChanged(startTimestamp);
    }

    function setCloseTimestamp(uint256 _closeTimestamp) public onlyOwner {
        require(startTimestamp != 0, 'Staking: start timestamp needs to be set first');
        require(closeTimestamp == 0, 'Staking: close timestamp already set');
        require(_closeTimestamp > startTimestamp, 'Staking: close timestamp needs to be higher than start one!');
        closeTimestamp = _closeTimestamp;
        emit CloseTimestampChanged(closeTimestamp);
    }

    function isStarted() public view returns (bool) {
        return startTimestamp != 0 && block.timestamp >= startTimestamp;
    }

    function isStopped() public view returns (bool) {
        return closeTimestamp != 0 && block.timestamp >= closeTimestamp;
    }

    function withdrawRemaining(address addr) public onlyOwner {
        require(startTimestamp != 0, 'Staking: start timestamp needs to be set first');
        
        for (uint256 i=0; i<maxPid; i++) {
            updatePool(i);
        }

        uint256 allTokenRewarded = 0;
        uint256 allTokenReceived = 0;

        for (uint256 i=0; i<maxPid; i++) {
            allTokenRewarded = allTokenRewarded.add(poolInfo[i].tokenRewarded);
            allTokenReceived = allTokenReceived.add(poolInfo[i].tokenReceived);
        }

        uint256 unlockedAmount = 0;
        uint256 possibleAmount = extrToken.balanceOf(address(this));
        uint256 reservedAmount = allTokenRewarded.sub(allTokenReceived);

        if (address(baseToken) == address(extrToken)) {
            for (uint i=0; i<maxPid; i++) {
                reservedAmount = reservedAmount.add(poolInfo[i].tokenRealStaked);
            }
        }

        if (possibleAmount > reservedAmount) {
            unlockedAmount = possibleAmount.sub(reservedAmount);
        }
        if (unlockedAmount > 0) {
            extrToken.safeTransfer(addr, unlockedAmount);
            emit WithdrawnRemain(addr, 0, address(extrToken), unlockedAmount);
        }
    }
    
    function withdrawEmergency(address addr) public onlyOwner {
        uint256 possibleAmount;
        possibleAmount = baseToken.balanceOf(address(this));
        if (possibleAmount > 0) {
            baseToken.safeTransfer(addr, possibleAmount);
            emit WithdrawnRemain(addr, 0, address(baseToken), possibleAmount);
        }
        possibleAmount = extrToken.balanceOf(address(this));
        if (possibleAmount > 0) {
            extrToken.safeTransfer(addr, possibleAmount);
            emit WithdrawnRemain(addr, 0, address(extrToken), possibleAmount);
        }
    }

    function pendingRewards(uint256 pid, address addr) external view returns (uint256) {
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startTimestamp > 0 && block.timestamp >= startTimestamp, 'Staking: not started yet');
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][addr];
        uint256 tokenPerShare = pool.tokenPerShare;
        uint256 lastMintedTimestamp = pool.rewardTimestamp;
        
        if (lastMintedTimestamp == 0) {
            lastMintedTimestamp = startTimestamp;
        }
        uint256 rewardTimestamp = getRewardTimestamp();
        if (rewardTimestamp == 0) {
            return 0;
        }
        if (rewardTimestamp > lastMintedTimestamp && pool.tokenRealStaked != 0) {
            uint256 multiplier = rewardTimestamp.sub(lastMintedTimestamp);
            uint256 tokenReward = multiplier.mul(tokenPerSecond).mul(pool.poolShare).div(totalPoolShare);
            tokenPerShare = tokenPerShare.add(tokenReward.mul(1e12).div(pool.tokenRealStaked));
        }
        uint256 pending = user.amount.mul(tokenPerShare).div(1e12).sub(user.rewardDebt);
        uint256 pendingRewardsTemp = user.pendingRewards;

        // WORKAROUND FOR EXPIRING LOCK
        if (pool.lockupTimerange != 0) {
            uint256 lastUserRewardTimestamp = user.rewardTimestamp;
            if (lastUserRewardTimestamp == 0) {
                lastUserRewardTimestamp = startTimestamp;
            }
            if (user.lockedTimestamp < rewardTimestamp) {
                if (lastUserRewardTimestamp < user.lockedTimestamp) {
                    pending = pending
                        .mul(user.lockedTimestamp.sub(lastUserRewardTimestamp))
                        .div(rewardTimestamp.sub(lastUserRewardTimestamp));
                } else {
                    pending = 0;
                }
            }
        }

        if (pending > 0 && user.isLocked) {
            pendingRewardsTemp = pendingRewardsTemp.add(pending);
        }
        
        return pendingRewardsTemp;
    }

    function deposit(uint256 pid, uint256 amount) external {
        // amount eq to zero is allowed
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startTimestamp > 0 && block.timestamp >= startTimestamp, 'Staking: not started yet');
        require(closeTimestamp == 0 || block.timestamp <= closeTimestamp, 'Staking: staking has ended, please withdraw remaining tokens');
        
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require(pool.tokenTotalLimit == 0 || pool.tokenTotalLimit >= pool.tokenRealStaked.add(amount),
            'Staking: you cannot deposit over the limit!');

        instantReseal(pid);

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);
        
        if (amount > 0) {
            user.amount = user.amount.add(amount);
            pool.tokenRealStaked = pool.tokenRealStaked.add(amount);
            baseToken.safeTransferFrom(address(msg.sender), address(this), amount);
            emit Deposited(msg.sender, pid, address(baseToken), amount);
        }
        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
    }

    function freeUnlock(uint256 pid) external {
        UserInfo storage user = userInfo[pid][msg.sender];
        bool worked;
        if (user.lockedTimestamp > 0 && user.lockedTimestamp <= block.timestamp) {
            instantUnlock(pid);
            worked = true;
        }
        if (user.unbondTimestamp > 0 && user.unbondTimestamp <= block.timestamp) {
            instantUnbond(pid);
            worked = true;
        }
        require(worked, 'Staking: cannot unlock/unbond before timelock finishes!');
    }

    function withdraw(uint256 pid, uint256 amount) external {
        // amount eq to zero is allowed
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startTimestamp > 0 && block.timestamp >= startTimestamp, 'Staking: not started yet');

        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require((!user.isLocked && block.timestamp >= user.lockedTimestamp) || isStopped(),
            'Staking: you cannot withdraw before unlock!');
        require((!user.isLocked && block.timestamp >= user.unbondTimestamp) || isStopped(),
            'Staking: you cannot withdraw before unbond!');
        require(user.amount >= amount, 'Staking: you cannot withdraw more than you have!');
        
        instantUnseal(pid);

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            pool.tokenRealStaked = pool.tokenRealStaked.sub(amount);
            baseToken.safeTransfer(address(msg.sender), amount);
            emit Withdrawn(msg.sender, pid, address(baseToken), amount);
        }
        
        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
    }

    function claim(uint256 pid) external {
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startTimestamp > 0 && block.timestamp >= startTimestamp, 'Staking: not started yet');

        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        if (user.pendingRewards > 0) {
            uint256 claimedAmount = transferPendingRewards(pid, msg.sender, user.pendingRewards);
            emit WithdrawnReward(msg.sender, pid, address(baseToken), claimedAmount);
            user.pendingRewards = user.pendingRewards.sub(claimedAmount);
            pool.tokenReceived = pool.tokenReceived.add(claimedAmount);
        }
        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
    }

    function instantReseal(uint256 pid) internal returns (bool) {
        unsafeRelock(pid);
        return true;
    }

    function instantUnlock(uint256 pid) internal returns (bool) {
        UserInfo storage user = userInfo[pid][msg.sender];
        if (user.lockedTimestamp > 0) {
            unsafeUnlock(pid);
            user.lockedTimestamp = 0;
            return true;
        }
        return false;
    }

    function instantUnbond(uint256 pid) internal returns (bool) {
        UserInfo storage user = userInfo[pid][msg.sender];
        if (user.unbondTimestamp > 0) {
            unsafeUnbond(pid);
            user.lockedTimestamp = 0;
            return true;
        }
        return false;
    }

    function instantUnseal(uint256 pid) internal returns (bool) {
        bool unlockNeeded = instantUnlock(pid);
        bool unbondNeeded = instantUnbond(pid);
        return unlockNeeded || unbondNeeded;
    }

    function unsafeRelock(uint256 pid) internal {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        user.lockedTimestamp = block.timestamp.add(pool.lockupTimerange);
        user.unbondTimestamp = 0;
        user.isLocked = true;

        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
        emit LockChanged(msg.sender, pid, user.lockedTimestamp, 0);
    }

    function unsafeUnlock(uint256 pid) internal {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        user.lockedTimestamp = 0;
        user.unbondTimestamp = block.timestamp.add(pool.unbondTimerange);
        user.isLocked = false;

        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
        emit LockChanged(msg.sender, pid, 0, user.unbondTimestamp);
    }

    function unsafeUnbond(uint256 pid) internal {
        UserInfo storage user = userInfo[pid][msg.sender];

        user.lockedTimestamp = 0;
        user.unbondTimestamp = 0;

        emit LockChanged(msg.sender, pid, 0, 0);
    }

    function addPool(uint256 _poolShare, uint256 _lockupTimerange, uint256 _unbondTimerange, uint256 _tokenTotalLimit) 
    internal {
        require(_poolShare > 0, 'Staking: Pool share needs to be higher than zero!');
        require(maxPid < 10, 'Staking: Cannot add more than 10 pools!');

        poolInfo.push(PoolInfo({
            poolShare: _poolShare,
            rewardTimestamp: 0,
            tokenPerShare: 0,
            tokenRealStaked: 0,
            tokenReceived: 0,
            tokenRewarded: 0,
            tokenTotalLimit: _tokenTotalLimit,
            lockupTimerange: _lockupTimerange,
            unbondTimerange: _unbondTimerange
        }));
        totalPoolShare = totalPoolShare.add(_poolShare);
        maxPid = maxPid.add(1);
    }

    function updatePool(uint256 pid) internal {
        if (pid >= maxPid) {
            return;
        }
        if (startTimestamp == 0 || block.timestamp < startTimestamp) {
            return;
        }
        PoolInfo storage pool = poolInfo[pid];
        if (pool.rewardTimestamp == 0) {
            pool.rewardTimestamp = startTimestamp;
        }
        uint256 rewardTimestamp = getRewardTimestamp();
        if (rewardTimestamp <= pool.rewardTimestamp) {
            return;
        }
        uint256 poolTokenRealStaked = pool.tokenRealStaked;
        if (poolTokenRealStaked == 0) {
            return;
        }
        uint256 multiplier = rewardTimestamp.sub(pool.rewardTimestamp);
        uint256 tokenReward = multiplier.mul(tokenPerSecond).mul(pool.poolShare).div(totalPoolShare);
        pool.tokenRewarded = pool.tokenRewarded.add(tokenReward);
        pool.tokenPerShare = pool.tokenPerShare.add(tokenReward.mul(1e12).div(poolTokenRealStaked));
        pool.rewardTimestamp = rewardTimestamp;
    }

    function updatePendingRewards(uint256 pid, address addr) internal {
        if (pid >= maxPid) {
            return;
        }
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][addr];
        uint256 pending = user.amount.mul(pool.tokenPerShare).div(1e12).sub(user.rewardDebt);
        
        // WORKAROUND FOR EXPIRING LOCK
        if (pool.lockupTimerange != 0) {
            uint256 lastUserRewardTimestamp = user.rewardTimestamp;
            if (lastUserRewardTimestamp == 0) {
                lastUserRewardTimestamp = startTimestamp;
            }
            if (user.lockedTimestamp < pool.rewardTimestamp) {
                if (lastUserRewardTimestamp < user.lockedTimestamp) {
                    pending = pending
                        .mul(user.lockedTimestamp.sub(lastUserRewardTimestamp))
                        .div(pool.rewardTimestamp.sub(lastUserRewardTimestamp));
                } else {
                    pending = 0;
                }
            }
        }

        user.rewardTimestamp = pool.rewardTimestamp;
        if (pending > 0 && user.isLocked) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
    }

    function transferPendingRewards(uint256 pid, address to, uint256 amount) internal returns (uint256) {
        if (pid >= maxPid) {
            return 0;
        }
        if (amount == 0) {
            return 0;
        }
        uint256 tokenAmount = extrToken.balanceOf(address(this));
        if (tokenAmount == 0) {
            return 0;
        }
        if (tokenAmount > amount) {
            tokenAmount = amount;
        }
        extrToken.safeTransfer(to, tokenAmount);
        return tokenAmount;
    }

    function getRewardTimestamp() internal view returns (uint256) {
        if (startTimestamp == 0) return 0;
        if (closeTimestamp == 0) return block.timestamp;
        return (closeTimestamp < block.timestamp) ? closeTimestamp : block.timestamp;
    }
}
