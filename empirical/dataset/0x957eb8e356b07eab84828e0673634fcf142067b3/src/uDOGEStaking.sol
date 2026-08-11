// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title uDOGEStaking
 * @dev uDOGE 的币天加权抽奖质押金库。
 * 接收来自 Hook 的 1% 质押大奖池分配，在大奖池积累奖金并被触发时，为质押者抽取里程碑 Jackpot 奖金。
 */
contract uDOGEStaking is Ownable, ReentrancyGuard {

    struct UserInfo {
        uint256 amount;       // 质押的代币数
        uint256 depositBlock; // 质押开始的区块
        uint256 accumulatedTickets; // 已经累积的币天积分
    }

    IERC20 public uDOGE;
    address public hookContract;

    // 质押数据跟踪
    mapping(address => UserInfo) public userInfo;
    address[] public stakers;
    mapping(address => bool) public isStaker;
    mapping(address => uint256) public stakerIndex; // 记录每个质押者在 stakers 数组中的索引

    // 抽奖历史与里程碑大奖状态
    uint256 public totalStaked;
    uint256 public activeJackpotRound; // 当前抽奖轮次 (1 to 10)
    uint256 public lastJackpotDrawBlock; // 上一次抽奖发生的区块

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event JackpotDrawn(uint256 round, address indexed winner1, address indexed winner2, address indexed winner3, uint256 prizePerWinner);

    modifier onlyHook() {
        require(msg.sender == hookContract, "uDOGEStaking: Only Hook can call");
        _;
    }

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /**
     * @dev 初始化代币与 Hook 合约地址
     */
    function initialize(address _token, address _hook) external onlyOwner {
        require(address(uDOGE) == address(0), "Already initialized");
        uDOGE = IERC20(_token);
        hookContract = _hook;
        lastJackpotDrawBlock = block.number;
    }

    /**
     * @dev 获取用户当前的“币天加权”抽奖票数（Tickets）
     */
    function getUserTickets(address user) public view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.amount == 0) return info.accumulatedTickets;
        
        // 票数 = 历史累积票数 + (当前区块 - 上次存入区块) * 质押代币数
        uint256 newTickets = (block.number - info.depositBlock) * info.amount;
        return info.accumulatedTickets + newTickets;
    }

    /**
     * @dev 质押 uDOGE 获得币天票仓
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        UserInfo storage info = userInfo[msg.sender];
        
        // 1. 在更新质押量之前，先锁死并滚存之前的“币天”积分
        if (info.amount > 0) {
            info.accumulatedTickets = getUserTickets(msg.sender);
        }
        
        info.amount += amount;
        info.depositBlock = block.number;

        // 2. 转移代币并跟踪质押者名录
        uDOGE.transferFrom(msg.sender, address(this), amount);
        totalStaked += amount;

        if (!isStaker[msg.sender]) {
            stakerIndex[msg.sender] = stakers.length;
            stakers.push(msg.sender);
            isStaker[msg.sender] = true;
        }

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev 取回质押的代币，同时提取/结算币天
     */
    function withdraw(uint256 amount) external nonReentrant {
        UserInfo storage info = userInfo[msg.sender];
        require(info.amount >= amount, "Withdraw amount exceeds balance");

        // 1. 滚存并保留提取后的剩余票仓
        info.accumulatedTickets = getUserTickets(msg.sender);
        info.amount -= amount;
        info.depositBlock = block.number;

        // 2. 转移代币
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
     * @dev Hook 将抽奖池 ETH 在 V3 买入的 uDOGE 转入此合约，并自动触发里程碑摇号。
     *
     * 流程：
     *   1. Hook 在调用本函数前已对本合约 approve tokenAmount
     *   2. 本合约 transferFrom Hook 拉取该数量 uDOGE
     *   3. 摇出 3 位幸运儿，用 uDOGE 均分派奖
     *
     * @param tokenAmount Hook 传入的 uDOGE 数量（已经对本地址 approve）
     */
    function recordJackpotFeeInToken(uint256 tokenAmount) external onlyHook nonReentrant {
        // Gas 预留检查：transferFrom × 4 + 事件至少需要 10 万 Gas
        require(gasleft() >= 100_000, "Staking: Insufficient gas for jackpot draw");
        require(tokenAmount > 0, "Staking: No jackpot fund");

        // 先从 Hook 拉取本轮 uDOGE 到合约（成功后合约余额自动包含历史顺延金额）
        uDOGE.transferFrom(msg.sender, address(this), tokenAmount);

        activeJackpotRound++;

        // 如果当前没有人在质押，资金已安全存入合约，顺延到下次开奖时自动累加
        if (totalStaked == 0 || stakers.length == 0) {
            return;
        }

        // 使用合约当前持有的全部 uDOGE 余额（含历史顺延积累），全部派发给本轮中奖者
        uint256 totalPrize = uDOGE.balanceOf(address(this));
        require(totalPrize > 0, "Staking: No prize to distribute");

        // 使用高度防碰撞链上伪随机特征摇出 3 名幸运儿
        // 利用 prevrandao (PoS 下的防篡改随机值)、区块哈希以及 stakers 数量做碰撞源
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            totalStaked,
            stakers.length
        )));

        address winner1 = _selectWeightedWinner(randomSeed);
        address winner2 = _selectWeightedWinner(uint256(keccak256(abi.encode(randomSeed, 1))));
        address winner3 = _selectWeightedWinner(uint256(keccak256(abi.encode(randomSeed, 2))));

        // 均分合约全部 uDOGE 余额（含历史顺延奖金）给 3 名中奖者
        uint256 prizePerWinner = totalPrize / 3;

        uDOGE.transfer(winner1, prizePerWinner);
        uDOGE.transfer(winner2, prizePerWinner);
        uDOGE.transfer(winner3, prizePerWinner);
        // 注：可能剩余最多 2 wei 整除误差，自动留存合约作为下轮种子奖金

        // 中奖后重置该用户的币天票仓（中大奖后币天清零，重新累积以示公平）
        _resetUserTickets(winner1);
        _resetUserTickets(winner2);
        _resetUserTickets(winner3);

        lastJackpotDrawBlock = block.number;

        emit JackpotDrawn(activeJackpotRound, winner1, winner2, winner3, prizePerWinner);
    }

    /**
     * @dev 依据“币天票仓权重”动态抽取中奖人
     */
    function _selectWeightedWinner(uint256 seed) internal view returns (address) {
        // 计算全体质押者的票数总和
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
            // 如果没有人有币天（全刚存入），在活跃质押者中随机均等抽选
            uint256 activeCount = 0;
            for (uint256 i = 0; i < stakers.length; i++) {
                if (isStaker[stakers[i]]) activeCount++;
            }
            if (activeCount == 0) return stakers[0]; // 防御性兜底
            
            uint256 targetIndex = seed % activeCount;
            uint256 currentIndex = 0;
            for (uint256 i = 0; i < stakers.length; i++) {
                if (isStaker[stakers[i]]) {
                    if (currentIndex == targetIndex) return stakers[i];
                    currentIndex++;
                }
            }
        }

        // 轮盘赌算法选出中奖人
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

    /**
     * @dev 中奖后重置该用户的币天票仓，让其公平重新排队
     */
    function _resetUserTickets(address user) internal {
        UserInfo storage info = userInfo[user];
        info.accumulatedTickets = 0;
        info.depositBlock = block.number; // 从中奖区块开始重新计算币天
    }

    // 允许质押合约接收 ETH
    receive() external payable {}
}
