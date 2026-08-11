// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/IPoolVault.sol";
import "../interfaces/ITrancheBudgetController.sol";

interface IArenaControllerRegistry {
    function isArenaController(address controller) external view returns (bool);
}

contract JudgmentObligationController is AccessControl, ReentrancyGuard {
    bytes32 public constant ARENA_ADMIN_ROLE = keccak256("ARENA_ADMIN_ROLE");

    uint256 public constant BPS_DENOMINATOR = 10_000;
    address public constant ETH_ASSET = address(0);

    IPoolVault public immutable poolVault;
    address public immutable asset;
    uint16 public immutable roundCapacityBps;
    uint16 public immutable maxOpenRounds;

    address public arena;
    uint256 public openRoundCount;

    struct RoundRisk {
        uint256 capacity;
        uint256 reservedObligation;
        uint256 reservedLoss;
        uint256 escrowedEntryAmount;
        bool opened;
        bool closed;
        bool aggregateSettled;
    }

    struct JudgmentRisk {
        uint256 roundId;
        address owner;
        uint256 entryAmount;
        uint256 maxReservedPayout;
        uint256 reservedVaultLoss;
        bool settled;
        bool aggregateReserved;
    }

    mapping(uint256 => RoundRisk) public rounds;
    mapping(uint256 => JudgmentRisk) public judgments;

    event ArenaUpdated(address indexed previousArena, address indexed newArena);
    event RoundCapacityOpened(uint256 indexed roundId, uint256 capacity);
    event JudgmentObligationCommitted(
        uint256 indexed roundId,
        uint256 indexed judgmentId,
        address indexed owner,
        uint256 entryAmount,
        uint256 maxReservedPayout,
        uint256 reservedVaultLoss
    );
    event JudgmentObligationSettled(
        uint256 indexed roundId,
        uint256 indexed judgmentId,
        address indexed owner,
        uint256 payoutAmount,
        uint256 actualVaultLoss
    );
    event JudgmentReservedPayoutIncreased(
        uint256 indexed roundId,
        uint256 indexed judgmentId,
        uint256 previousMaxReservedPayout,
        uint256 newMaxReservedPayout,
        uint256 additionalReservedVaultLoss
    );
    event RoundReservedPayoutIncreased(
        uint256 indexed roundId,
        uint256 additionalReservedPayout,
        uint256 reservedObligation,
        uint256 additionalReservedVaultLoss
    );
    event RoundClosed(uint256 indexed roundId);
    event RoundPayoutPoolSettled(
        uint256 indexed roundId,
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    );
    event EngineRiskReserved(uint256 amount);
    event EngineRiskSettled(
        uint256 reservedRisk,
        uint256 realizedLoss,
        uint256 realizedProfit
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidBps();
    error InvalidArena();
    error InvalidAsset();
    error InvalidRound();
    error InvalidJudgment();
    error ArenaAlreadySet();
    error RoundAlreadyOpened();
    error RoundClosedAlready();
    error TooManyOpenRounds();
    error CapacityExceeded();
    error EngineRiskBudgetExceeded();
    error JudgmentAlreadyExists();
    error JudgmentAlreadySettled();
    error OwnerMismatch();
    error PayoutExceedsReserved();
    error RoundHasOpenObligations();
    error OnlyArena();

    constructor(
        address poolVault_,
        address admin_,
        address arenaAdmin_,
        uint16 roundCapacityBps_,
        uint16 maxOpenRounds_
    ) {
        if (
            poolVault_ == address(0) ||
            admin_ == address(0) ||
            arenaAdmin_ == address(0)
        ) {
            revert InvalidAddress();
        }
        if (
            roundCapacityBps_ == 0 ||
            roundCapacityBps_ > BPS_DENOMINATOR ||
            maxOpenRounds_ == 0
        ) {
            revert InvalidBps();
        }

        poolVault = IPoolVault(poolVault_);
        asset = IPoolVault(poolVault_).asset();
        roundCapacityBps = roundCapacityBps_;
        maxOpenRounds = maxOpenRounds_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ARENA_ADMIN_ROLE, arenaAdmin_);
    }

    function setArena(address newArena) external onlyRole(ARENA_ADMIN_ROLE) {
        if (newArena == address(0)) {
            revert InvalidAddress();
        }
        if (arena != address(0)) {
            revert ArenaAlreadySet();
        }
        if (
            newArena.code.length == 0 ||
            !IArenaControllerRegistry(newArena).isArenaController(address(this))
        ) {
            revert InvalidArena();
        }

        address previousArena = arena;
        arena = newArena;

        emit ArenaUpdated(previousArena, newArena);
    }

    function openRoundCapacity(
        uint256 roundId
    ) external nonReentrant onlyArena returns (uint256 capacity) {
        if (roundId == 0) {
            revert InvalidRound();
        }

        RoundRisk storage round = rounds[roundId];
        if (round.opened) {
            revert RoundAlreadyOpened();
        }
        if (openRoundCount >= maxOpenRounds) {
            revert TooManyOpenRounds();
        }

        capacity =
            (poolVault.totalAssets() * roundCapacityBps) /
            BPS_DENOMINATOR;
        if (capacity == 0) {
            revert InvalidAmount();
        }

        round.capacity = capacity;
        round.opened = true;
        openRoundCount += 1;
        poolVault.openBusinessRound();

        emit RoundCapacityOpened(roundId, capacity);
    }

    function commitJudgmentEth(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxReservedPayout
    ) external payable nonReentrant onlyArena {
        if (asset != ETH_ASSET) {
            revert InvalidAsset();
        }
        if (msg.value != entryAmount) {
            revert InvalidAmount();
        }

        _commitJudgment(
            roundId,
            judgmentId,
            owner,
            entryAmount,
            maxReservedPayout,
            maxReservedPayout,
            false
        );
        poolVault.receiveBusinessEth{value: entryAmount}(
            entryAmount,
            maxReservedPayout
        );
    }

    function commitJudgmentFromWallet(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxReservedPayout
    ) external nonReentrant onlyArena {
        if (asset == ETH_ASSET) {
            revert InvalidAsset();
        }

        _commitJudgment(
            roundId,
            judgmentId,
            owner,
            entryAmount,
            maxReservedPayout,
            maxReservedPayout,
            false
        );
        poolVault.receiveBusinessAssetFrom(
            owner,
            entryAmount,
            maxReservedPayout
        );
    }

    function commitAggregateJudgmentEth(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxPayoutAmount
    ) external payable nonReentrant onlyArena {
        if (asset != ETH_ASSET) {
            revert InvalidAsset();
        }
        if (msg.value != entryAmount) {
            revert InvalidAmount();
        }

        _commitJudgment(
            roundId,
            judgmentId,
            owner,
            entryAmount,
            maxPayoutAmount,
            0,
            true
        );
        poolVault.receiveBusinessEth{value: entryAmount}(entryAmount, 0);
    }

    function commitAggregateJudgmentFromWallet(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxPayoutAmount
    ) external nonReentrant onlyArena {
        if (asset == ETH_ASSET) {
            revert InvalidAsset();
        }

        _commitJudgment(
            roundId,
            judgmentId,
            owner,
            entryAmount,
            maxPayoutAmount,
            0,
            true
        );
        poolVault.receiveBusinessAssetFrom(owner, entryAmount, 0);
    }

    function increaseReservedPayout(
        uint256 judgmentId,
        uint256 newMaxReservedPayout
    ) external nonReentrant onlyArena {
        JudgmentRisk storage judgment = judgments[judgmentId];
        if (judgment.owner == address(0)) {
            revert InvalidJudgment();
        }
        if (judgment.settled) {
            revert JudgmentAlreadySettled();
        }
        if (judgment.aggregateReserved) {
            revert InvalidJudgment();
        }
        if (newMaxReservedPayout <= judgment.maxReservedPayout) {
            return;
        }

        RoundRisk storage round = rounds[judgment.roundId];
        if (!round.opened || round.closed) {
            revert InvalidRound();
        }

        uint256 additionalReservedPayout = newMaxReservedPayout -
            judgment.maxReservedPayout;
        if (
            round.reservedObligation + additionalReservedPayout > round.capacity
        ) {
            revert CapacityExceeded();
        }

        uint256 previousReservedVaultLoss = judgment.reservedVaultLoss;
        uint256 newReservedVaultLoss = newMaxReservedPayout >
            judgment.entryAmount
            ? newMaxReservedPayout - judgment.entryAmount
            : 0;
        uint256 additionalReservedVaultLoss = 0;
        if (newReservedVaultLoss > previousReservedVaultLoss) {
            additionalReservedVaultLoss =
                newReservedVaultLoss -
                previousReservedVaultLoss;
            _reserveEngineRisk(additionalReservedVaultLoss);
        }

        uint256 previousMaxReservedPayout = judgment.maxReservedPayout;
        judgment.maxReservedPayout = newMaxReservedPayout;
        judgment.reservedVaultLoss = newReservedVaultLoss;
        round.reservedObligation += additionalReservedPayout;
        round.reservedLoss += additionalReservedVaultLoss;

        poolVault.increaseBusinessPayoutReserve(additionalReservedPayout);

        emit JudgmentReservedPayoutIncreased(
            judgment.roundId,
            judgmentId,
            previousMaxReservedPayout,
            newMaxReservedPayout,
            additionalReservedVaultLoss
        );
    }

    function increaseRoundReservedPayout(
        uint256 roundId,
        uint256 additionalReservedPayout
    ) external nonReentrant onlyArena {
        if (additionalReservedPayout == 0) {
            revert InvalidAmount();
        }

        RoundRisk storage round = rounds[roundId];
        if (!round.opened || round.closed) {
            revert InvalidRound();
        }

        uint256 additionalReservedVaultLoss = _increaseRoundReserve(
            round,
            additionalReservedPayout
        );
        poolVault.increaseBusinessPayoutReserve(additionalReservedPayout);

        emit RoundReservedPayoutIncreased(
            roundId,
            additionalReservedPayout,
            round.reservedObligation,
            additionalReservedVaultLoss
        );
    }

    function settleJudgment(
        uint256 judgmentId,
        uint256 payoutAmount
    ) external nonReentrant onlyArena {
        JudgmentRisk storage judgment = judgments[judgmentId];
        if (judgment.owner == address(0)) {
            revert InvalidJudgment();
        }
        if (judgment.settled) {
            revert JudgmentAlreadySettled();
        }
        if (judgment.aggregateReserved) {
            revert InvalidJudgment();
        }
        if (payoutAmount > judgment.maxReservedPayout) {
            revert PayoutExceedsReserved();
        }

        judgment.settled = true;

        RoundRisk storage round = rounds[judgment.roundId];
        if (round.aggregateSettled || round.closed) {
            revert RoundClosedAlready();
        }
        round.reservedObligation -= judgment.maxReservedPayout;
        round.reservedLoss -= judgment.reservedVaultLoss;
        round.escrowedEntryAmount -= judgment.entryAmount;

        uint256 actualVaultLoss = payoutAmount > judgment.entryAmount
            ? payoutAmount - judgment.entryAmount
            : 0;
        uint256 realizedProfit = judgment.entryAmount > payoutAmount
            ? judgment.entryAmount - payoutAmount
            : 0;
        _settleEngineRisk(
            judgment.reservedVaultLoss,
            actualVaultLoss,
            realizedProfit
        );

        if (payoutAmount > 0) {
            poolVault.businessPayout(
                judgment.owner,
                payoutAmount,
                judgment.entryAmount,
                judgment.maxReservedPayout
            );
        } else {
            poolVault.businessPayout(
                judgment.owner,
                0,
                judgment.entryAmount,
                judgment.maxReservedPayout
            );
        }

        emit JudgmentObligationSettled(
            judgment.roundId,
            judgmentId,
            judgment.owner,
            payoutAmount,
            actualVaultLoss
        );
    }

    function settleRoundPayoutPool(
        uint256 roundId,
        uint256 totalPayoutAmount
    ) external nonReentrant onlyArena {
        RoundRisk storage round = rounds[roundId];
        if (!round.opened) {
            revert InvalidRound();
        }
        if (round.closed) {
            revert RoundClosedAlready();
        }
        if (totalPayoutAmount > round.reservedObligation) {
            revert PayoutExceedsReserved();
        }

        uint256 receivedAmount = round.escrowedEntryAmount;
        uint256 reservedPayoutAmount = round.reservedObligation;
        uint256 actualVaultLoss = totalPayoutAmount > receivedAmount
            ? totalPayoutAmount - receivedAmount
            : 0;
        uint256 realizedProfit = receivedAmount > totalPayoutAmount
            ? receivedAmount - totalPayoutAmount
            : 0;
        _settleEngineRisk(round.reservedLoss, actualVaultLoss, realizedProfit);

        if (receivedAmount != 0 || reservedPayoutAmount != 0) {
            poolVault.settleBusinessPayoutPool(
                totalPayoutAmount,
                receivedAmount,
                reservedPayoutAmount
            );
        } else if (totalPayoutAmount != 0) {
            revert PayoutExceedsReserved();
        }

        round.reservedObligation = 0;
        round.reservedLoss = 0;
        round.escrowedEntryAmount = 0;
        round.aggregateSettled = true;
        round.closed = true;
        openRoundCount -= 1;
        poolVault.closeBusinessRound();

        emit RoundPayoutPoolSettled(
            roundId,
            totalPayoutAmount,
            receivedAmount,
            reservedPayoutAmount
        );
        emit RoundClosed(roundId);
    }

    function allocateSettledJudgmentPayout(
        uint256 judgmentId,
        uint256 payoutAmount
    ) external nonReentrant onlyArena {
        (uint256 roundId, address owner, uint256 actualVaultLoss) = _settleJudgmentPayout(
            judgmentId,
            payoutAmount
        );
        if (payoutAmount > 0) {
            poolVault.allocateBusinessPayout(owner, payoutAmount);
        }

        emit JudgmentObligationSettled(
            roundId,
            judgmentId,
            owner,
            payoutAmount,
            actualVaultLoss
        );
    }

    function allocateAndClaimSettledJudgmentPayout(
        uint256 judgmentId,
        uint256 payoutAmount,
        address receiver
    ) external nonReentrant onlyArena {
        if (receiver == address(0)) {
            revert InvalidAddress();
        }
        (uint256 roundId, address owner, uint256 actualVaultLoss) = _settleJudgmentPayout(
            judgmentId,
            payoutAmount
        );
        if (payoutAmount > 0) {
            poolVault.allocateAndClaimBusinessPayout(
                owner,
                receiver,
                payoutAmount
            );
        }

        emit JudgmentObligationSettled(
            roundId,
            judgmentId,
            owner,
            payoutAmount,
            actualVaultLoss
        );
    }

    function _settleJudgmentPayout(
        uint256 judgmentId,
        uint256 payoutAmount
    ) private returns (uint256 roundId, address owner, uint256 actualVaultLoss) {
        JudgmentRisk storage judgment = judgments[judgmentId];
        if (judgment.owner == address(0)) {
            revert InvalidJudgment();
        }
        if (judgment.settled) {
            revert JudgmentAlreadySettled();
        }

        RoundRisk storage round = rounds[judgment.roundId];
        if (!round.aggregateSettled || !round.closed) {
            revert InvalidRound();
        }
        if (payoutAmount > judgment.maxReservedPayout) {
            revert PayoutExceedsReserved();
        }

        judgment.settled = true;
        actualVaultLoss = payoutAmount > judgment.entryAmount
            ? payoutAmount - judgment.entryAmount
            : 0;
        roundId = judgment.roundId;
        owner = judgment.owner;
    }

    function closeRound(uint256 roundId) external nonReentrant onlyArena {
        RoundRisk storage round = rounds[roundId];
        if (!round.opened) {
            revert InvalidRound();
        }
        if (round.closed) {
            revert RoundClosedAlready();
        }
        if (
            round.reservedObligation != 0 ||
            round.reservedLoss != 0 ||
            round.escrowedEntryAmount != 0
        ) {
            revert RoundHasOpenObligations();
        }

        round.closed = true;
        openRoundCount -= 1;
        poolVault.closeBusinessRound();

        emit RoundClosed(roundId);
    }

    function getEngineRiskRemaining() external view returns (uint256) {
        return
            ITrancheBudgetController(poolVault.budgetController())
                .getRiskRemaining(address(poolVault));
    }

    function _commitJudgment(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxPayoutAmount,
        uint256 reservedPayoutAmount,
        bool aggregateReserved
    ) private {
        if (judgmentId == 0 || owner == address(0)) {
            revert InvalidJudgment();
        }
        if (entryAmount == 0 || maxPayoutAmount == 0) {
            revert InvalidAmount();
        }
        if (judgments[judgmentId].owner != address(0)) {
            revert JudgmentAlreadyExists();
        }

        RoundRisk storage round = rounds[roundId];
        if (!round.opened || round.closed) {
            revert InvalidRound();
        }
        if (round.reservedObligation + reservedPayoutAmount > round.capacity) {
            revert CapacityExceeded();
        }

        uint256 reservedVaultLoss = reservedPayoutAmount > entryAmount
            ? reservedPayoutAmount - entryAmount
            : 0;
        _reserveEngineRisk(reservedVaultLoss);

        round.reservedObligation += reservedPayoutAmount;
        round.reservedLoss += reservedVaultLoss;
        round.escrowedEntryAmount += entryAmount;
        judgments[judgmentId] = JudgmentRisk({
            roundId: roundId,
            owner: owner,
            entryAmount: entryAmount,
            maxReservedPayout: maxPayoutAmount,
            reservedVaultLoss: reservedVaultLoss,
            settled: false,
            aggregateReserved: aggregateReserved
        });

        emit JudgmentObligationCommitted(
            roundId,
            judgmentId,
            owner,
            entryAmount,
            maxPayoutAmount,
            reservedVaultLoss
        );
    }

    function _increaseRoundReserve(
        RoundRisk storage round,
        uint256 additionalReservedPayout
    ) private returns (uint256 additionalReservedVaultLoss) {
        uint256 previousReservedObligation = round.reservedObligation;
        uint256 newReservedObligation = previousReservedObligation +
            additionalReservedPayout;
        if (newReservedObligation > round.capacity) {
            revert CapacityExceeded();
        }

        uint256 newReservedVaultLoss = newReservedObligation >
            round.escrowedEntryAmount
            ? newReservedObligation - round.escrowedEntryAmount
            : 0;
        if (newReservedVaultLoss > round.reservedLoss) {
            additionalReservedVaultLoss =
                newReservedVaultLoss -
                round.reservedLoss;
            _reserveEngineRisk(additionalReservedVaultLoss);
            round.reservedLoss = newReservedVaultLoss;
        }

        round.reservedObligation = newReservedObligation;
    }

    function _reserveEngineRisk(uint256 reservedVaultLoss) private {
        if (reservedVaultLoss == 0) {
            return;
        }

        ITrancheBudgetController budgetController = ITrancheBudgetController(
            poolVault.budgetController()
        );
        if (
            budgetController.getRiskRemaining(address(poolVault)) <
            reservedVaultLoss
        ) {
            revert EngineRiskBudgetExceeded();
        }

        budgetController.reserveEngineRisk(
            address(poolVault),
            reservedVaultLoss
        );
        emit EngineRiskReserved(reservedVaultLoss);
    }

    function _settleEngineRisk(
        uint256 reservedRisk,
        uint256 realizedLoss,
        uint256 realizedProfit
    ) private {
        if (reservedRisk == 0 && realizedLoss == 0 && realizedProfit == 0) {
            return;
        }
        ITrancheBudgetController(poolVault.budgetController()).settleEngineRisk(
            address(poolVault),
            reservedRisk,
            realizedLoss,
            realizedProfit
        );
        emit EngineRiskSettled(reservedRisk, realizedLoss, realizedProfit);
    }

    modifier onlyArena() {
        if (msg.sender != arena) {
            revert OnlyArena();
        }
        _;
    }
}
