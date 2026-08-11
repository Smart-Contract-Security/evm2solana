// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title uDOGEStaking
 */
contract uDOGEStaking is Ownable, ReentrancyGuard {

    struct UserInfo {
        uint256 amount;
        uint256 depositBlock;
        uint256 accumulatedTickets;
    }

    IERC20 public uDOGE;
    address public hookContract;


    mapping(address => UserInfo) public userInfo;
    address[] public stakers;
    mapping(address => bool) public isStaker;
    mapping(address => uint256) public stakerIndex;


    uint256 public totalStaked;
    uint256 public activeJackpotRound;
    uint256 public lastJackpotDrawBlock;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event JackpotDrawn(uint256 round, address indexed winner1, address indexed winner2, address indexed winner3, uint256 prizePerWinner);

    modifier onlyHook() {
        require(msg.sender == hookContract, "uDOGEStaking: Only Hook can call");
        _;
    }

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    
    function initialize(address _token, address _hook) external onlyOwner {
        require(address(uDOGE) == address(0), "Already initialized");
        uDOGE = IERC20(_token);
        hookContract = _hook;
        lastJackpotDrawBlock = block.number;
    }

    
    function getUserTickets(address user) public view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.amount == 0) return info.accumulatedTickets;
        

        uint256 newTickets = (block.number - info.depositBlock) * info.amount;
        return info.accumulatedTickets + newTickets;
    }

    
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        UserInfo storage info = userInfo[msg.sender];
        

        if (info.amount > 0) {
            info.accumulatedTickets = getUserTickets(msg.sender);
        }
        
        info.amount += amount;
        info.depositBlock = block.number;


        uDOGE.transferFrom(msg.sender, address(this), amount);
        totalStaked += amount;

        if (!isStaker[msg.sender]) {
            stakerIndex[msg.sender] = stakers.length;
            stakers.push(msg.sender);
            isStaker[msg.sender] = true;
        }

        emit Staked(msg.sender, amount);
    }

    
    function withdraw(uint256 amount) external nonReentrant {
        UserInfo storage info = userInfo[msg.sender];
        require(info.amount >= amount, "Withdraw amount exceeds balance");


        info.accumulatedTickets = getUserTickets(msg.sender);
        info.amount -= amount;
        info.depositBlock = block.number;


        totalStaked -= amount;
        uDOGE.transfer(msg.sender, amount);

        if (info.amount == 0) {
            uint256 indexToRemove = stakerIndex[msg.sender];
            uint256 lastIndex = stakers.length - 1;
            if (indexToRemove != lastIndex) {
                address lastStaker = stakers[lastIndex];
                stakers[indexToRemove] = lastStaker;
                stakerIndex[lastStaker] = indexToRemove;
            }
            stakers.pop();
            isStaker[msg.sender] = false;
        }

        emit Withdrawn(msg.sender, amount);
    }

    /**
     *
     *
     */
    function recordJackpotFeeInToken(uint256 tokenAmount) external onlyHook nonReentrant {

        require(gasleft() >= 100_000, "Staking: Insufficient gas for jackpot draw");
        require(tokenAmount > 0, "Staking: No jackpot fund");


        uDOGE.transferFrom(msg.sender, address(this), tokenAmount);

        activeJackpotRound++;


        if (totalStaked == 0 || stakers.length == 0) {
            return;
        }


        uint256 totalPrize = uDOGE.balanceOf(address(this));
        require(totalPrize > 0, "Staking: No prize to distribute");



        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            totalStaked,
            stakers.length
        )));

        address winner1 = _selectWeightedWinner(randomSeed);
        address winner2 = _selectWeightedWinner(uint256(keccak256(abi.encode(randomSeed, 1))));
        address winner3 = _selectWeightedWinner(uint256(keccak256(abi.encode(randomSeed, 2))));


        uint256 prizePerWinner = totalPrize / 3;

        uDOGE.transfer(winner1, prizePerWinner);
        uDOGE.transfer(winner2, prizePerWinner);
        uDOGE.transfer(winner3, prizePerWinner);



        _resetUserTickets(winner1);
        _resetUserTickets(winner2);
        _resetUserTickets(winner3);

        lastJackpotDrawBlock = block.number;

        emit JackpotDrawn(activeJackpotRound, winner1, winner2, winner3, prizePerWinner);
    }

    
    function _selectWeightedWinner(uint256 seed) internal view returns (address) {

        uint256 sumTickets = 0;
        uint256[] memory ticketsList = new uint256[](stakers.length);
        
        for (uint256 i = 0; i < stakers.length; i++) {
            if (isStaker[stakers[i]]) {
                uint256 tickets = getUserTickets(stakers[i]);
                ticketsList[i] = tickets;
                sumTickets += tickets;
            }
        }

        if (sumTickets == 0) {

            uint256 activeCount = 0;
            for (uint256 i = 0; i < stakers.length; i++) {
                if (isStaker[stakers[i]]) activeCount++;
            }
            if (activeCount == 0) return stakers[0];
            
            uint256 targetIndex = seed % activeCount;
            uint256 currentIndex = 0;
            for (uint256 i = 0; i < stakers.length; i++) {
                if (isStaker[stakers[i]]) {
                    if (currentIndex == targetIndex) return stakers[i];
                    currentIndex++;
                }
            }
        }


        uint256 targetValue = seed % sumTickets;
        uint256 currentSum = 0;

        for (uint256 i = 0; i < stakers.length; i++) {
            if (isStaker[stakers[i]]) {
                currentSum += ticketsList[i];
                if (currentSum > targetValue) {
                    return stakers[i];
                }
            }
        }

        return stakers[0];
    }

    
    function _resetUserTickets(address user) internal {
        UserInfo storage info = userInfo[user];
        info.accumulatedTickets = 0;
        info.depositBlock = block.number;
    }


    receive() external payable {}
}
