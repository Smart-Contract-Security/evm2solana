// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISymbiontNFTNew {
    function walletToTokenId(address wallet) external view returns (uint256);
    function symbionts(uint256 tokenId) external view returns (
        uint256 health,
        uint256 balanceAtMint,
        uint256 rarityTier,
        uint256 birthTime,
        uint256 lastUpdateTime,
        uint256 lastFeedTime,
        uint256 feedCountToday
    );
    function updateHealth(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function isEligible(address wallet) external view returns (bool eligible, uint256 health);
}

contract RewardPool is Ownable, ReentrancyGuard {
    ISymbiontNFTNew public symbiontNFT;
    IERC20 public token;
    
    uint256 public lastDistributionTime;
    uint256 public distributionInterval = 7 days;
    uint256 public totalDistributed;
    uint256 public totalClaimed;
    
    uint256 public currentEpoch;
    mapping(uint256 => uint256) public epochRewardPool;
    mapping(uint256 => uint256) public epochTotalScore;
    mapping(uint256 => mapping(address => uint256)) public epochUserScore;
    mapping(uint256 => mapping(address => bool)) public epochClaimed;
    
    event RewardDistributed(uint256 indexed epoch, uint256 totalReward, uint256 totalScore);
    event RewardClaimed(address indexed user, uint256 indexed epoch, uint256 amount);
    event RewardPoolFunded(uint256 amount);
    event SYMBReceived(address indexed from, uint256 amount);
    event UnclaimedETHRecovered(address indexed caller, uint256 amount);
    event DistributionIntervalUpdated(uint256 newInterval);
    
    constructor(address _symbiontNFT, address _token) Ownable(msg.sender) {
        require(_symbiontNFT != address(0), "Invalid NFT");
        require(_token != address(0), "Invalid token");
        symbiontNFT = ISymbiontNFTNew(_symbiontNFT);
        token = IERC20(_token);
        lastDistributionTime = block.timestamp;
    }
    
    function setSymbiontNFT(address _symbiontNFT) external onlyOwner {
        require(_symbiontNFT != address(0), "Invalid NFT");
        symbiontNFT = ISymbiontNFTNew(_symbiontNFT);
    }
    
    /**
     * @notice Update distribution interval (only owner)
     */
    function setDistributionInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 1 days, "Min 1 day");
        require(_interval <= 30 days, "Max 30 days");
        distributionInterval = _interval;
        emit DistributionIntervalUpdated(_interval);
    }
    
    function fundRewardPool() external payable {
        require(msg.value > 0, "Zero amount");
        emit RewardPoolFunded(msg.value);
    }
    
    receive() external payable {
        emit RewardPoolFunded(msg.value);
    }
    
    /**
     * @notice Calculate user's reward score
     * @dev Score = health × balance (in wei)
     * Returns 0 if health ≤ 50% (not eligible for rewards)
     * Higher balance = higher reward share (buy power incentive)
     * Rarity is cosmetic only — no multiplier in rewards
     */
    function calculateUserScore(address user) public returns (uint256) {
        uint256 tokenId = symbiontNFT.walletToTokenId(user);
        if (tokenId == 0) return 0;
        
        // Update health based on time decay first
        symbiontNFT.updateHealth(tokenId);
        
        // Get health — must be > 50 to be eligible
        (uint256 health,,,,,, ) = symbiontNFT.symbionts(tokenId);
        if (health <= 50) return 0; // NOT ELIGIBLE
        
        // Balance factor: more SYMB held = more reward share
        uint256 balance = token.balanceOf(user);
        
        return health * balance;
    }
    
    /**
     * @notice Distribute rewards to holders
     * @dev Users with health ≤ 50% are excluded from allocation entirely.
     * Their share is redistributed to eligible holders.
     */
    function distributeRewards(address[] calldata holders) external onlyOwner nonReentrant {
        require(block.timestamp >= lastDistributionTime + distributionInterval, "Too early");
        
        uint256 rewardPool = address(this).balance;
        require(rewardPool > 0, "No rewards to distribute");
        require(holders.length > 0, "No holders");
        
        uint256 totalScore = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            uint256 score = calculateUserScore(holders[i]);
            if (score > 0) {
                epochUserScore[currentEpoch][holders[i]] = score;
                totalScore += score;
            }
            // If score == 0 (health ≤ 50 or no NFT), user is excluded
            // Their share goes to eligible holders proportionally
        }
        
        require(totalScore > 0, "No valid scores");
        
        epochRewardPool[currentEpoch] = rewardPool;
        epochTotalScore[currentEpoch] = totalScore;
        
        lastDistributionTime = block.timestamp;
        
        emit RewardDistributed(currentEpoch, rewardPool, totalScore);
        
        currentEpoch++;
    }
    
    function claimReward(uint256 epoch) external nonReentrant {
        require(epoch < currentEpoch, "Epoch not finalized");
        require(!epochClaimed[epoch][msg.sender], "Already claimed");
        
        uint256 userScore = epochUserScore[epoch][msg.sender];
        require(userScore > 0, "No rewards");
        
        uint256 totalScore = epochTotalScore[epoch];
        uint256 rewardPool = epochRewardPool[epoch];
        
        uint256 reward = (userScore * rewardPool) / totalScore;
        require(reward > 0, "Zero reward");
        
        epochClaimed[epoch][msg.sender] = true;
        totalDistributed += reward;
        totalClaimed += reward;
        
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");
        
        emit RewardClaimed(msg.sender, epoch, reward);
    }
    
    function claimAllRewards() external nonReentrant {
        uint256 totalReward = 0;
        
        for (uint256 epoch = 0; epoch < currentEpoch; epoch++) {
            if (epochClaimed[epoch][msg.sender]) continue;
            
            uint256 userScore = epochUserScore[epoch][msg.sender];
            if (userScore == 0) continue;
            
            uint256 totalScore = epochTotalScore[epoch];
            uint256 rewardPool = epochRewardPool[epoch];
            
            uint256 reward = (userScore * rewardPool) / totalScore;
            if (reward > 0) {
                epochClaimed[epoch][msg.sender] = true;
                totalReward += reward;
                emit RewardClaimed(msg.sender, epoch, reward);
            }
        }
        
        require(totalReward > 0, "No rewards to claim");
        totalDistributed += totalReward;
        totalClaimed += totalReward;
        
        (bool success, ) = msg.sender.call{value: totalReward}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Get claimable rewards for user
     * @dev Returns 0 if user was not eligible (health ≤ 50%) at distribution time
     */
    function getClaimableRewards(address user) external view returns (uint256) {
        uint256 totalReward = 0;
        
        for (uint256 epoch = 0; epoch < currentEpoch; epoch++) {
            if (epochClaimed[epoch][user]) continue;
            
            uint256 userScore = epochUserScore[epoch][user];
            if (userScore == 0) continue;
            
            uint256 totalScore = epochTotalScore[epoch];
            uint256 rewardPool = epochRewardPool[epoch];
            
            uint256 reward = (userScore * rewardPool) / totalScore;
            totalReward += reward;
        }
        
        return totalReward;
    }
    
    /**
     * @notice Check if user is currently eligible for rewards
     * @return eligible True if health > 50%
     * @return health Current health value
     */
    function isEligibleForReward(address user) external view returns (bool eligible, uint256 health) {
        return symbiontNFT.isEligible(user);
    }
    
    function getUserScorePreview(address user) external returns (uint256) {
        return calculateUserScore(user);
    }
    
    function claimETH() external onlyOwner nonReentrant {
        uint256 unclaimed = totalDistributed - totalClaimed;
        require(unclaimed > 0, "No unclaimed ETH");
        
        uint256 ethBalance = address(this).balance;
        if (unclaimed > ethBalance) {
            unclaimed = ethBalance;
        }
        
        totalClaimed += unclaimed;
        
        (bool success, ) = msg.sender.call{value: unclaimed}("");
        require(success, "ETH transfer failed");
        
        emit UnclaimedETHRecovered(msg.sender, unclaimed);
    }
    
    function getUnclaimedETH() external view returns (uint256) {
        uint256 unclaimed = totalDistributed - totalClaimed;
        uint256 ethBalance = address(this).balance;
        return unclaimed > ethBalance ? ethBalance : unclaimed;
    }
}
