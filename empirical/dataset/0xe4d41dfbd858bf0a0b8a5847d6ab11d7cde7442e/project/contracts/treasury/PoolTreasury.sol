// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title PoolTreasury
 * @notice Autonomous treasury for the MADE ecosystem.
 *
 * @dev CRITICAL: This contract has NO admin keys. NO owner. NO pause.
 *      NO emergency withdraw. Once deployed, it runs forever autonomously.
 *
 *      Funded purely by:
 *        1. Stamp fees from CreationRegistry ($0.20 per ring)
 *
 *      Outflows:
 *        1. Monthly distribution to active creators (80% of balance)
 *        2. Batch caller rewards (0.001 ETH per processBatch call)
 *
 *      Distribution formula:
 *        "Your share = (rings you added this month / total rings this month) × distributable"
 *
 *      Dust tracking (Fix: precision issues):
 *        Rounding errors from integer division are tracked in `undistributedDust`.
 *        Dust rolls into the next month's distribution instead of being lost.
 *
 *      Batch caller reward (Fix 6):
 *        Anyone who calls CreationRegistry.processBatch() gets paid 0.001 ETH.
 *        This ensures the system runs forever even without the team.
 *
 *      Uses pull pattern: sets claimable amounts, doesn't push ETH.
 *      Protected by ReentrancyGuard (Fix 2).
 */
contract PoolTreasury is ReentrancyGuard {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Time between distributions
    uint256 public constant DISTRIBUTION_INTERVAL = 30 days;

    /// @notice Percentage of pool distributed each month
    uint256 public constant DISTRIBUTION_PERCENTAGE = 80;

    /// @notice ETH reward for batch callers (Fix 6)
    uint256 public constant BATCH_CALLER_REWARD = 0.001 ether;

    // ─────────────────────────────────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice MADECore contract address
    address public immutable madeCore;

    /// @notice CreationRegistry contract address
    address public immutable registryContract;

    /// @notice Timestamp of last distribution
    uint256 public lastDistributionTimestamp;

    /// @notice Total ETH ever distributed
    uint256 public totalDistributed;

    /// @notice Current month counter
    uint256 public currentMonth;

    /// @notice Accumulated rounding dust from distributions
    uint256 public undistributedDust;

    /// @notice Monthly ring counts per token: month => tokenId => rings added
    mapping(uint256 => mapping(uint256 => uint256)) public monthlyRings;

    /// @notice Total rings added in a month
    mapping(uint256 => uint256) public monthlyTotalRings;

    /// @notice Active participant token IDs per month
    mapping(uint256 => uint256[]) public monthlyParticipants;

    /// @notice Dedup: whether token is already a participant this month
    mapping(uint256 => mapping(uint256 => bool)) private _isParticipant;

    /// @notice Total earnings per holder address
    mapping(address => uint256) public totalEarnings;

    /// @notice Already claimed per holder
    mapping(address => uint256) public claimedEarnings;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event FundsReceived(address indexed sender, uint256 amount);
    event RingsRecorded(uint256 indexed tokenId, uint256 month, uint256 count);
    event DistributionCompleted(uint256 indexed month, uint256 amount, uint256 recipientCount);
    event EarningsClaimed(address indexed holder, uint256 amount);
    event BatchCallerRewarded(address indexed caller, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error OnlyRegistry();
    error DistributionNotReady();
    error NothingToClaim();
    error TransferFailed();
    error InsufficientBalance();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address _madeCore, address _registry) {
        madeCore = _madeCore;
        registryContract = _registry;
        lastDistributionTimestamp = block.timestamp;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Receive ETH
    // ─────────────────────────────────────────────────────────────────────────

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Ring Recording
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Record ring additions for monthly distribution.
     * @dev Called by CreationRegistry during batch processing.
     * @param tokenId The MADE token that added rings.
     * @param count Number of rings added.
     */
    function recordRings(uint256 tokenId, uint256 count) external {
        if (msg.sender != registryContract) revert OnlyRegistry();

        uint256 month = currentMonth;
        monthlyRings[month][tokenId] += count;
        monthlyTotalRings[month] += count;

        if (!_isParticipant[month][tokenId]) {
            _isParticipant[month][tokenId] = true;
            monthlyParticipants[month].push(tokenId);
        }

        emit RingsRecorded(tokenId, month, count);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Batch Caller Reward — Fix 6
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Pay the batch caller reward. Only callable by CreationRegistry.
     * @dev Best-effort: if treasury doesn't have enough ETH, does not revert.
     *      The batch processing itself is more important than the reward.
     * @param caller The address to pay the reward to.
     */
    function payBatchCallerReward(address caller) external nonReentrant {
        if (msg.sender != registryContract) revert OnlyRegistry();

        if (address(this).balance >= BATCH_CALLER_REWARD) {
            (bool sent,) = caller.call{value: BATCH_CALLER_REWARD}("");
            if (sent) {
                emit BatchCallerRewarded(caller, BATCH_CALLER_REWARD);
            }
            // If send fails, silently continue — reward is best-effort
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Distribution — Fix: Dust tracking
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Execute monthly distribution.
     * @dev Callable by anyone after DISTRIBUTION_INTERVAL elapsed.
     *
     *      Distribution = 80% of (current balance + accumulated dust).
     *      Dust = distributable - sum(all shares). Rolled into next month.
     *
     *      Uses pull pattern: credits totalEarnings[owner], doesn't push ETH.
     */
    function distribute() external nonReentrant {
        if (block.timestamp < lastDistributionTimestamp + DISTRIBUTION_INTERVAL) {
            revert DistributionNotReady();
        }

        uint256 month = currentMonth;
        uint256 totalRings = monthlyTotalRings[month];

        // No activity this month: advance and return
        if (totalRings == 0) {
            lastDistributionTimestamp = block.timestamp;
            currentMonth++;
            emit DistributionCompleted(month, 0, 0);
            return;
        }

        // Calculate distributable: 80% of balance + accumulated dust
        uint256 poolBalance = address(this).balance;
        uint256 distributable = ((poolBalance + undistributedDust) * DISTRIBUTION_PERCENTAGE) / 100;

        uint256 recipientCount = monthlyParticipants[month].length;
        uint256 actualDistributed = 0;

        // Calculate each participant's share
        for (uint256 i = 0; i < recipientCount;) {
            uint256 tokenId = monthlyParticipants[month][i];
            uint256 tokenRings = monthlyRings[month][tokenId];

            uint256 share = (distributable * tokenRings) / totalRings;
            actualDistributed += share;

            // Look up token owner to credit earnings
            (bool success, bytes memory data) = madeCore.staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", tokenId)
            );

            if (success && data.length >= 32) {
                address owner = abi.decode(data, (address));
                totalEarnings[owner] += share;
            }

            unchecked { ++i; }
        }

        // Track dust: rounding errors roll into next month
        undistributedDust = distributable - actualDistributed;

        totalDistributed += actualDistributed;
        lastDistributionTimestamp = block.timestamp;
        currentMonth++;

        emit DistributionCompleted(month, actualDistributed, recipientCount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claims — Fix 2: ReentrancyGuard
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim accumulated pool earnings.
     * @dev Pull pattern. Protected by ReentrancyGuard.
     */
    function claim() external nonReentrant {
        uint256 unclaimed = totalEarnings[msg.sender] - claimedEarnings[msg.sender];
        if (unclaimed == 0) revert NothingToClaim();

        // CEI: update state before external call
        claimedEarnings[msg.sender] = totalEarnings[msg.sender];

        (bool success,) = msg.sender.call{value: unclaimed}("");
        if (!success) revert TransferFailed();

        emit EarningsClaimed(msg.sender, unclaimed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    function getCurrentPoolSize() external view returns (uint256) {
        return address(this).balance;
    }

    function getNextDistributionDate() external view returns (uint256) {
        return lastDistributionTimestamp + DISTRIBUTION_INTERVAL;
    }

    function getUnclaimedEarnings(address holder) external view returns (uint256) {
        return totalEarnings[holder] - claimedEarnings[holder];
    }

    function getCurrentMonthParticipants() external view returns (uint256) {
        return monthlyParticipants[currentMonth].length;
    }

    function getEarnings(address holder) external view returns (
        uint256 total,
        uint256 claimed,
        uint256 unclaimed
    ) {
        total = totalEarnings[holder];
        claimed = claimedEarnings[holder];
        unclaimed = total - claimed;
    }

    function getPoolInfo() external view returns (
        uint256 totalBalance,
        uint256 _totalDistributed,
        uint256 lastDistribution,
        uint256 nextDistribution,
        uint256 dust
    ) {
        totalBalance = address(this).balance;
        _totalDistributed = totalDistributed;
        lastDistribution = lastDistributionTimestamp;
        nextDistribution = lastDistributionTimestamp + DISTRIBUTION_INTERVAL;
        dust = undistributedDust;
    }
}
