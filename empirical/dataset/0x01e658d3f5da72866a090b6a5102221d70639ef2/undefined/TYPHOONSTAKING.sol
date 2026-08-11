/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TYPHOONStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum StakingTier {
        Flexible,
        LockedFirstTier,
        LockedSecondTier,
        LockedThirdTier
    }

    struct StakingDetails {
        uint256 lockDuration;
        uint256 claimRewardsDuration;
        uint256 rewardsAPR;
        uint256 minStakeAmount;
    }

    struct userStakingInfo {
        uint256 stakingTier;
        uint256 stakingIndex;
        uint256 stakedAmount;
        uint256 stakingStartTime;
        uint256 stakingEndTime;
        uint256 lastClaimTime;
    }

    struct Round {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardAmount;
        uint256 totalTickets;
        uint256 totalParticipants;
        address[] participantList;
        address[] winners;
        bool isStarted;
        bool isEnded;
    }

    struct UserLotteryParams {
        uint256 tierOneTotalStaking;
        uint256 tierTwoTotalStaking;
        uint256 tierThreeTotalStaking;
        uint256 totalStaked;
        uint256 tickets;
    }

    mapping(uint256 => Round) private lotteryRounds;
    mapping(address => UserLotteryParams) private userLotteryParams;

    mapping(StakingTier => StakingDetails) private stakingTiers;

    //user => tier => stakingIndex => amount
    mapping(address => mapping(StakingTier => userStakingInfo[]))
        private userStakes;

    mapping(address => mapping(StakingTier => uint256))
        private userStakingInTier;

    mapping(address => uint256) private userWholeStaking;
    mapping(address => mapping(StakingTier => uint256))
        private userTierClaimedRewards;

    IERC20 public TYPHOONToken;
    uint256 public TYPHOONTotalSupply;
    uint256 public totalStaked;
    uint256 public currentRoundId = 1;

    uint256[] public tierOneLimits = new uint256[](2);
    uint256[] public tierTwoLimits = new uint256[](2);
    uint256[] public tierThreeLimits = new uint256[](2);

    uint256 public tierOneBaseTickets = 1;
    uint256 public tierTwoBaseTickets = 2;
    uint256 public tierThreeBaseTickets = 4;

    event Staked(address indexed user, StakingTier tier, uint256 amount);
    event Unstaked(address indexed user, StakingTier tier, uint256 amount);
    event RewardsClaimed(
        address indexed user,
        StakingTier tier,
        uint256 amount
    );
    event StakingDetailsUpdated(
        StakingTier tier,
        uint256 newLockDuration,
        uint256 newAPY
    );

    constructor(address _TYPHOONToken) Ownable(msg.sender) {
        TYPHOONToken = IERC20(_TYPHOONToken);
        TYPHOONTotalSupply = TYPHOONToken.totalSupply();

        tierOneLimits[0] = (TYPHOONTotalSupply * 25) / 100000; //0.025 %
        tierOneLimits[1] = (TYPHOONTotalSupply * 5) / 10000; //0.05 %
        tierTwoLimits[0] = (TYPHOONTotalSupply * 1) / 1000; //0.1 %
        tierTwoLimits[1] = (TYPHOONTotalSupply * 25) / 10000; //0.25 %
        tierThreeLimits[0] = (TYPHOONTotalSupply * 5) / 1000; //0.5 %
        tierThreeLimits[1] = (TYPHOONTotalSupply * 1) / 100; //1 %
        stakingTiers[StakingTier.Flexible] = StakingDetails(
            0 days,
            24 hours,
            30,
            1 * 10**18
        );
        stakingTiers[StakingTier.LockedFirstTier] = StakingDetails(
            7 days,
            7 days,
            50,
            1 * 10**18
        );
        stakingTiers[StakingTier.LockedSecondTier] = StakingDetails(
            14 days,
            14 days,
            75,
            1 * 10**18
        );
        stakingTiers[StakingTier.LockedThirdTier] = StakingDetails(
            28 days,
            28 days,
            100,
            1 * 10**18
        );
    }

    function getStakingDetails(StakingTier tier)
        external
        view
        returns (
            uint256 stakingDuration,
            uint256 claimRewardsCycle,
            uint256 rewardsAPR,
            uint256 minStakeAmount
        )
    {
        return (
            stakingTiers[tier].lockDuration,
            stakingTiers[tier].claimRewardsDuration,
            stakingTiers[tier].rewardsAPR,
            stakingTiers[tier].minStakeAmount
        );
    }

    function getUserStake(StakingTier tier, address user)
        public
        view
        returns (userStakingInfo[] memory)
    {
        return userStakes[user][tier];
    }

    function getStakeStartTime(
        StakingTier tier,
        address user,
        uint256 stakingIndex
    ) public view returns (uint256) {
        return userStakes[user][tier][stakingIndex].stakingStartTime;
    }

    function getStakeEndTime(
        StakingTier tier,
        address user,
        uint256 stakingIndex
    ) public view returns (uint256) {
        return
            userStakes[user][tier][stakingIndex].stakingStartTime +
            stakingTiers[tier].lockDuration;
    }

    function getStakeAmountAndTime(
        StakingTier tier,
        address user,
        uint256 stakingIndex
    )
        public
        view
        returns (
            uint256 stakingStartTime,
            uint256 stakingEndTime,
            uint256 stakedAmount
        )
    {
        return (
            userStakes[user][tier][stakingIndex].stakingStartTime,
            userStakes[user][tier][stakingIndex].stakingStartTime +
                stakingTiers[tier].lockDuration,
            userStakes[user][tier][stakingIndex].stakedAmount
        );
    }

    function getUserTierClaimedRewards(StakingTier tier, address user)
        external
        view
        returns (uint256)
    {
        return userTierClaimedRewards[user][tier];
    }

    function getUserNoOfStakes(StakingTier tier, address user)
        public
        view
        returns (uint256)
    {
        return userStakes[user][tier].length;
    }

    function getUserStakingInTier(address user, StakingTier tier)
        public
        view
        returns (uint256)
    {
        return userStakingInTier[user][tier];
    }

    function getUserWholeStaking(address user) public view returns (uint256) {
        return userWholeStaking[user];
    }

    function setTYPHOONTokenAddress(address _TYPHOONToken) external onlyOwner {
        TYPHOONToken = IERC20(_TYPHOONToken);
        TYPHOONTotalSupply = TYPHOONToken.totalSupply();
    }

    function updateStakingDetails(
        StakingTier tier,
        uint256 newLockDuration,
        uint256 newAPR
    ) public onlyOwner {
        StakingDetails storage details = stakingTiers[tier];
        details.lockDuration = newLockDuration;
        details.rewardsAPR = newAPR;
        emit StakingDetailsUpdated(tier, newLockDuration, newAPR);
    }

    function getLOtteryRoundData(uint256 roundId)
        external
        view
        returns (Round memory)
    {
        return lotteryRounds[roundId];
    }

    function getUserLotteryParams(address user)
        external
        view
        returns (UserLotteryParams memory)
    {
        return userLotteryParams[user];
    }

    function stake(StakingTier tier, uint256 amount) external nonReentrant {
        require(
            stakingTiers[tier].claimRewardsDuration > 0,
            "Invalid staking tier"
        );
        require(
            amount >= stakingTiers[tier].minStakeAmount,
            "Below minimum stake amount"
        );

        TYPHOONToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 stakingIndex = userStakes[msg.sender][tier].length;
        userStakingInfo memory stakeInfo = userStakingInfo({
            stakingTier: uint256(tier),
            stakingIndex: stakingIndex,
            stakedAmount: amount,
            stakingStartTime: block.timestamp,
            stakingEndTime: block.timestamp + stakingTiers[tier].lockDuration,
            lastClaimTime: block.timestamp
        });

        if (
            block.timestamp > lotteryRounds[currentRoundId].endTime &&
            lotteryRounds[currentRoundId].isStarted
        ) {
            finalizeLotteryRound();
        } else if (
            !lotteryRounds[currentRoundId].isStarted &&
            !lotteryRounds[currentRoundId].isEnded
        ) {
            Round storage round = lotteryRounds[currentRoundId];
            round.startTime = block.timestamp;
            round.endTime = block.timestamp + 3 days;
            round.rewardAmount = 40000 * 10**18;
            round.isStarted = true;
        }

        userStakes[msg.sender][tier].push(stakeInfo);
        userStakingInTier[msg.sender][tier] += amount;
        userWholeStaking[msg.sender] += amount;
        totalStaked += amount;
        addUserLotteryStakings(msg.sender, tier, amount);

        emit Staked(msg.sender, tier, amount);
    }

    function unstake(StakingTier tier, uint256 stakingIndex)
        external
        nonReentrant
    {
        require(
            stakingTiers[tier].claimRewardsDuration > 0,
            "Invalid staking tier"
        );
        require(
            userStakes[msg.sender][tier].length > stakingIndex,
            "Invalid index"
        );
        require(
            userStakes[msg.sender][tier][stakingIndex].stakedAmount > 0,
            "No stake to unstake"
        );

        uint256 unlockTime = userStakes[msg.sender][tier][stakingIndex]
            .stakingStartTime + stakingTiers[tier].lockDuration;
        require(block.timestamp > unlockTime, "Staking still locked");

        uint256 stakedAmount = userStakes[msg.sender][tier][stakingIndex]
            .stakedAmount;

        uint256 rewards = calculateTierStakingIndexRewards(
            msg.sender,
            tier,
            stakingIndex
        );
        require(
            TYPHOONToken.balanceOf(address(this)) > stakedAmount + rewards,
            "Staking contract balance is insufficient"
        );
        if (rewards > 0) {
            userTierClaimedRewards[msg.sender][tier] += rewards;
            TYPHOONToken.safeTransfer(msg.sender, rewards);
        }
        userStakingInTier[msg.sender][tier] -= stakedAmount;
        userWholeStaking[msg.sender] -= stakedAmount;
        totalStaked -= stakedAmount;
        removeUserLotteryStakings(msg.sender, tier, stakedAmount);
        TYPHOONToken.safeTransfer(msg.sender, stakedAmount);

        uint256 lastIndex = userStakes[msg.sender][tier].length - 1;
        if (stakingIndex != lastIndex) {
            userStakes[msg.sender][tier][stakingIndex] = userStakes[msg.sender][
                tier
            ][lastIndex];
            userStakes[msg.sender][tier][stakingIndex]
                .stakingIndex = stakingIndex;
            userStakes[msg.sender][tier].pop();
        } else {
            userStakes[msg.sender][tier].pop();
        }

        emit Unstaked(msg.sender, tier, stakedAmount);
    }

    function extecuteLottery() external onlyOwner {
        if (
            block.timestamp > lotteryRounds[currentRoundId].endTime &&
            lotteryRounds[currentRoundId].isStarted
        ) {
            finalizeLotteryRound();
        }
    }

    function random(uint256 seed) private view returns (uint256) {
        require(seed != 0, "Seed must be greater than 0");
        return
            uint256(
                keccak256(
                    abi.encodePacked(block.prevrandao, block.timestamp, seed)
                )
            ) % seed;
    }

    function claimRewards(StakingTier tier) public nonReentrant {
        require(
            stakingTiers[tier].claimRewardsDuration > 0,
            "Invalid staking tier"
        );

        require(
            userStakes[msg.sender][tier].length > 0,
            "No stake to claim rewards"
        );
        uint256 index = userStakes[msg.sender][tier][0].stakingIndex;
        require(
            block.timestamp >
                userStakes[msg.sender][tier][index].lastClaimTime +
                    stakingTiers[tier].claimRewardsDuration,
            "Next claim time not reached"
        );
        uint256 rewards = calculateAndUpdateTierRewards(tier, msg.sender);
        if (rewards > 0) {
            userTierClaimedRewards[msg.sender][tier] += rewards;
            TYPHOONToken.safeTransfer(msg.sender, rewards);
        }

        emit RewardsClaimed(msg.sender, tier, rewards);
    }

    function calculateRewards(StakingTier tier, address user)
        public
        view
        returns (uint256)
    {
        uint256 stakingLength = getUserNoOfStakes(tier, user);
        uint256 claimableRewards;
        for (uint256 index = 0; index < stakingLength; index++) {
            claimableRewards += calculateTierStakingIndexRewards(
                user,
                tier,
                index
            );
        }
        return claimableRewards;
    }

    function finalizeLotteryRound() private {
        lotteryRounds[currentRoundId].isEnded = true;

        Round storage round = lotteryRounds[currentRoundId];

        if (round.totalParticipants >= 10) {
            uint256 totalTickets = round.totalTickets;
            address[] memory winners = new address[](5);
            address[] memory alreadyPicked = new address[](5);

            uint256 winnersCount = 0;
            while (winnersCount < 5) {
                uint256 winningTicket = random(totalTickets);
                uint256 count = 0;

                for (uint256 j = 0; j < round.totalParticipants; j++) {
                    address participant = round.participantList[j];
                    count += userLotteryParams[participant].tickets;

                    if (
                        count >= winningTicket &&
                        !isAlreadyPicked(
                            alreadyPicked,
                            participant,
                            winnersCount
                        )
                    ) {
                        winners[winnersCount] = participant;
                        alreadyPicked[winnersCount] = participant;
                        winnersCount++;
                        break;
                    }
                }
            }

            round.winners = winners;

            for (uint256 i = 0; i < winnersCount; i++) {
                TYPHOONToken.transfer(winners[i], round.rewardAmount);
            }
        }

        currentRoundId += 1;
        Round storage nextRound = lotteryRounds[currentRoundId];
        nextRound.startTime = block.timestamp;
        nextRound.endTime = block.timestamp + 3 days;
        nextRound.rewardAmount = 40000 * 10**18;
        nextRound.isStarted = true;
        nextRound.participantList = round.participantList;
    }

    // Helper function to check if a participant has already been picked as a winner
    function isAlreadyPicked(
        address[] memory alreadyPicked,
        address participant,
        uint256 count
    ) private pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (alreadyPicked[i] == participant) {
                return true;
            }
        }
        return false;
    }

    function removeFromParticipantList(address user, Round storage round)
        private
    {
        uint256 length = round.participantList.length;
        for (uint256 i = 0; i < length; i++) {
            if (round.participantList[i] == user) {
                round.participantList[i] = round.participantList[length - 1];
                round.participantList.pop();
                break;
            }
        }
    }

    function addUserLotteryStakings(
        address user,
        StakingTier tier,
        uint256 amount
    ) private {
        if (tier != StakingTier.Flexible) {
            UserLotteryParams storage params = userLotteryParams[user];
            Round storage round = lotteryRounds[currentRoundId];
            // Update total staked amount
            if (amount > 0) {
                params.totalStaked += amount;
            }

            if (tier == StakingTier.LockedFirstTier) {
                params.tierOneTotalStaking += amount;
            } else if (tier == StakingTier.LockedSecondTier) {
                params.tierTwoTotalStaking += amount;
            } else if (tier == StakingTier.LockedThirdTier) {
                params.tierThreeTotalStaking += amount;
            }

            uint256 previousTickets = params.tickets;
            uint256 newTickets = calculateLotteryTickets(params);
            round.totalTickets += newTickets - previousTickets;

            uint256 difference = 0;
            if (newTickets > previousTickets) {
                difference = newTickets - previousTickets;
            }
            round.totalTickets += difference;
            if (previousTickets == 0 && newTickets > 0) {
                round.totalParticipants += 1;
                round.participantList.push(user);
            }

            params.tickets = newTickets;
        }
    }

    function removeUserLotteryStakings(
        address user,
        StakingTier tier,
        uint256 amount
    ) private {
        if (tier != StakingTier.Flexible) {
            UserLotteryParams storage params = userLotteryParams[user];
            Round storage round = lotteryRounds[currentRoundId];

            // Update total staked amount
            if (amount > 0) {
                params.totalStaked -= amount;
            }

            if (tier == StakingTier.LockedFirstTier) {
                params.tierOneTotalStaking -= amount;
            } else if (tier == StakingTier.LockedSecondTier) {
                params.tierTwoTotalStaking -= amount;
            } else if (tier == StakingTier.LockedThirdTier) {
                params.tierThreeTotalStaking -= amount;
            }

            uint256 previousTickets = params.tickets;
            uint256 newTickets = calculateLotteryTickets(params);
            uint256 difference = 0;
            if (previousTickets > newTickets) {
                difference = previousTickets - newTickets;
            }
            round.totalTickets -= difference;
            if (previousTickets - newTickets == 0) {
                round.totalParticipants -= 1;
                removeFromParticipantList(user, round);
            }

            params.tickets = newTickets;
        }
    }

    function calculateLotteryTickets(UserLotteryParams storage params)
        private
        view
        returns (uint256)
    {
        uint256 tickets = 0;
        uint256 tierPoints;
        if (
            params.tierThreeTotalStaking > params.tierOneTotalStaking &&
            params.tierThreeTotalStaking > params.tierTwoTotalStaking
        ) {
            tierPoints = tierThreeBaseTickets;
        }
        if (
            params.tierTwoTotalStaking > params.tierOneTotalStaking &&
            params.tierTwoTotalStaking > params.tierThreeTotalStaking
        ) {
            tierPoints = tierTwoBaseTickets;
        }
        if (
            params.tierOneTotalStaking > params.tierTwoTotalStaking &&
            params.tierOneTotalStaking > params.tierThreeTotalStaking
        ) {
            tierPoints = tierThreeBaseTickets;
        }

        if (params.totalStaked >= tierThreeLimits[1]) {
            tickets += tierPoints * 13; //x13
        }

        if (
            params.totalStaked >= tierThreeLimits[0] &&
            params.totalStaked < tierThreeLimits[1]
        ) {
            tickets += tierPoints * 10; //x10
        }
        if (
            params.totalStaked >= tierTwoLimits[1] &&
            params.totalStaked < tierThreeLimits[0]
        ) {
            tickets += tierPoints * 7; //x7
        }

        if (
            params.totalStaked >= tierTwoLimits[0] &&
            params.totalStaked < tierTwoLimits[1]
        ) {
            tickets += tierPoints * 4; //x4
        }

        if (
            params.totalStaked >= tierOneLimits[1] &&
            params.totalStaked < tierTwoLimits[0]
        ) {
            tickets += tierPoints * 2; //x2
        }
        if (
            params.totalStaked >= tierOneLimits[0] &&
            params.totalStaked < tierOneLimits[1]
        ) {
            tickets += tierPoints * 1; // x1
        }

        return tickets;
    }

    function calculateTierStakingIndexRewards(
        address user,
        StakingTier tier,
        uint256 stakingIndex
    ) public view returns (uint256) {
        uint256 minStakedTime = userStakes[user][tier][stakingIndex]
            .lastClaimTime + stakingTiers[tier].claimRewardsDuration;
        if (block.timestamp < minStakedTime) {
            return 0;
        }
        uint256 stakedTime = block.timestamp -
            userStakes[user][tier][stakingIndex].lastClaimTime;
        uint256 rewards = (userStakes[user][tier][stakingIndex].stakedAmount *
            stakingTiers[tier].rewardsAPR *
            stakedTime) / (31536000 * 100);
        return rewards;
    }

    function calculateAndUpdateTierRewards(StakingTier tier, address user)
        internal
        returns (uint256)
    {
        uint256 stakingLength = getUserNoOfStakes(tier, user);
        uint256 claimableRewards;
        for (uint256 index = 0; index < stakingLength; index++) {
            uint256 rewards = calculateTierStakingIndexRewards(
                user,
                tier,
                index
            );
            if (rewards > 0) {
                userStakes[user][tier][index].lastClaimTime = block.timestamp;
            }
            claimableRewards += rewards;
        }
        return claimableRewards;
    }
}
