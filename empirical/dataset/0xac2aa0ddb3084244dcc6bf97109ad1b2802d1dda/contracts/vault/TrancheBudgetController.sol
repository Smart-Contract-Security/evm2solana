// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/IPoolVault.sol";

contract TrancheBudgetController is AccessControl, ReentrancyGuard {
    bytes32 public constant TRANCHE_ISSUER_ROLE = keccak256("TRANCHE_ISSUER_ROLE");
    bytes32 public constant GOVERNANCE_WITHDRAWER_ROLE = keccak256("GOVERNANCE_WITHDRAWER_ROLE");

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WINDOW_DURATION = 1 days;
    uint256 public constant RISK_BUCKET_DURATION = 1 hours;
    uint8 public constant RISK_BUCKET_COUNT = 24;

    uint16 public immutable dailyLimitBps;
    uint256 public nextTrancheId = 1;

    struct Tranche {
        address vault;
        uint256 remaining;
        uint64 expiresAt;
        bool canceled;
    }

    struct RiskBucket {
        uint64 startedAt;
        uint256 engineLoss;
        uint256 engineProfitOffset;
        uint256 governanceMoved;
    }

    struct RiskState {
        uint256 activeEngineRiskReserve;
        uint256 rollingEngineLoss;
        uint256 rollingEngineProfitOffset;
        uint256 rollingGovernanceMoved;
        mapping(uint8 => RiskBucket) buckets;
    }

    mapping(uint256 => Tranche) public tranches;
    mapping(address => RiskState) private riskStates;

    event TrancheIssued(uint256 indexed trancheId, address indexed vault, uint256 amount, uint64 expiresAt);
    event TrancheCanceled(uint256 indexed trancheId);
    event GovernanceWithdrawalExecuted(
        uint256 indexed trancheId,
        address indexed vault,
        address indexed recipient,
        uint256 amount,
        uint256 trancheRemaining,
        uint256 windowRemaining
    );
    event WindowOpened(address indexed vault, uint64 startedAt, uint256 limit);
    event EngineRiskReserved(
        address indexed vault,
        address indexed manager,
        uint256 amount,
        uint256 activeEngineRiskReserve,
        uint256 riskUsed,
        uint256 riskRemaining
    );
    event EngineRiskSettled(
        address indexed vault,
        address indexed manager,
        uint256 reservedRiskReleased,
        uint256 realizedLoss,
        uint256 profitOffset,
        uint256 activeEngineRiskReserve,
        uint256 riskUsed,
        uint256 riskRemaining
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidVault();
    error InvalidDailyLimit();
    error InvalidExpiry();
    error InvalidTranche();
    error TrancheCanceledAlready();
    error TrancheExpired();
    error TrancheBudgetExceeded();
    error DailyBudgetExceeded();
    error OnlyVaultBusinessController();
    error ActiveEngineRiskExceeded();
    error RiskStateInvariantBroken();

    constructor(
        address admin_,
        address trancheIssuer_,
        address governanceWithdrawer_,
        uint16 dailyLimitBps_
    ) {
        if (admin_ == address(0) || trancheIssuer_ == address(0) || governanceWithdrawer_ == address(0)) {
            revert InvalidAddress();
        }
        if (dailyLimitBps_ == 0 || dailyLimitBps_ > BPS_DENOMINATOR) {
            revert InvalidDailyLimit();
        }

        dailyLimitBps = dailyLimitBps_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(TRANCHE_ISSUER_ROLE, trancheIssuer_);
        _grantRole(GOVERNANCE_WITHDRAWER_ROLE, governanceWithdrawer_);
    }

    function issueTranche(address vault, uint256 amount, uint64 expiresAt)
        external
        onlyRole(TRANCHE_ISSUER_ROLE)
        returns (uint256 trancheId)
    {
        if (vault == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (expiresAt <= block.timestamp) {
            revert InvalidExpiry();
        }
        if (IPoolVault(vault).budgetController() != address(this)) {
            revert InvalidVault();
        }

        trancheId = nextTrancheId++;
        tranches[trancheId] = Tranche({vault: vault, remaining: amount, expiresAt: expiresAt, canceled: false});

        emit TrancheIssued(trancheId, vault, amount, expiresAt);
    }

    function cancelTranche(uint256 trancheId) external onlyRole(TRANCHE_ISSUER_ROLE) {
        Tranche storage tranche = tranches[trancheId];
        if (tranche.vault == address(0)) {
            revert InvalidTranche();
        }
        if (tranche.canceled) {
            revert TrancheCanceledAlready();
        }

        tranche.canceled = true;
        emit TrancheCanceled(trancheId);
    }

    function executeGovernanceWithdrawal(uint256 trancheId, address recipient, uint256 amount)
        external
        nonReentrant
        onlyRole(GOVERNANCE_WITHDRAWER_ROLE)
    {
        if (recipient == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }

        Tranche storage tranche = tranches[trancheId];
        if (tranche.vault == address(0)) {
            revert InvalidTranche();
        }
        if (tranche.canceled) {
            revert TrancheCanceledAlready();
        }
        if (block.timestamp > tranche.expiresAt) {
            revert TrancheExpired();
        }
        if (amount > tranche.remaining) {
            revert TrancheBudgetExceeded();
        }

        uint256 windowRemaining = _recordGovernanceMovement(tranche.vault, amount);
        tranche.remaining -= amount;

        IPoolVault(tranche.vault).withdrawByBudget(recipient, amount);

        emit GovernanceWithdrawalExecuted(
            trancheId,
            tranche.vault,
            recipient,
            amount,
            tranche.remaining,
            windowRemaining
        );
    }

    function getWindowRemaining(address vault) external view returns (uint256) {
        return _riskRemainingView(vault);
    }

    function getRiskRemaining(address vault) external view returns (uint256) {
        return _riskRemainingView(vault);
    }

    function getRiskUsed24h(address vault) external view returns (uint256) {
        (
            uint256 activeReserve,
            uint256 rollingEngineLoss,
            uint256 rollingEngineProfitOffset,
            uint256 rollingGovernanceMoved
        ) = _riskTotalsView(vault);

        return activeReserve + _engineNetLoss(rollingEngineLoss, rollingEngineProfitOffset) + rollingGovernanceMoved;
    }

    function getRollingEngineNetLoss24h(address vault) external view returns (uint256) {
        (, uint256 rollingEngineLoss, uint256 rollingEngineProfitOffset, ) = _riskTotalsView(vault);
        return _engineNetLoss(rollingEngineLoss, rollingEngineProfitOffset);
    }

    function getRollingGovernanceMove24h(address vault) external view returns (uint256) {
        (, , , uint256 rollingGovernanceMoved) = _riskTotalsView(vault);
        return rollingGovernanceMoved;
    }

    function getActiveEngineRiskReserve(address vault) external view returns (uint256) {
        return riskStates[vault].activeEngineRiskReserve;
    }

    function getRiskBucket(address vault, uint8 bucketIndex)
        external
        view
        returns (uint64 startedAt, uint256 engineLoss, uint256 engineProfitOffset, uint256 governanceMoved)
    {
        if (bucketIndex >= RISK_BUCKET_COUNT) {
            revert InvalidAmount();
        }

        RiskBucket storage bucket = riskStates[vault].buckets[bucketIndex];
        return (bucket.startedAt, bucket.engineLoss, bucket.engineProfitOffset, bucket.governanceMoved);
    }

    function reserveEngineRisk(address vault, uint256 amount) external nonReentrant {
        _enforceVaultBusinessController(vault);
        if (amount == 0) {
            return;
        }

        _refreshRiskWindow(vault);
        uint256 riskRemaining = _consumeRiskCapacity(vault, amount);
        RiskState storage state = riskStates[vault];
        state.activeEngineRiskReserve += amount;

        emit EngineRiskReserved(
            vault,
            msg.sender,
            amount,
            state.activeEngineRiskReserve,
            _riskUsed(state),
            riskRemaining
        );
    }

    function settleEngineRisk(address vault, uint256 reservedRisk, uint256 realizedLoss, uint256 realizedProfit)
        external
        nonReentrant
    {
        _enforceVaultBusinessController(vault);
        if (reservedRisk == 0 && realizedLoss == 0 && realizedProfit == 0) {
            return;
        }

        _refreshRiskWindow(vault);
        RiskState storage state = riskStates[vault];
        if (reservedRisk > state.activeEngineRiskReserve) {
            revert ActiveEngineRiskExceeded();
        }

        state.activeEngineRiskReserve -= reservedRisk;

        uint256 profitOffset = 0;
        if (realizedLoss != 0 || realizedProfit != 0) {
            (, RiskBucket storage bucket) = _currentRiskBucket(vault);
            if (realizedLoss != 0) {
                bucket.engineLoss += realizedLoss;
                state.rollingEngineLoss += realizedLoss;
            }
            if (realizedProfit != 0) {
                uint256 currentEngineNetLoss =
                    _engineNetLoss(state.rollingEngineLoss, state.rollingEngineProfitOffset);
                profitOffset = realizedProfit > currentEngineNetLoss ? currentEngineNetLoss : realizedProfit;
                if (profitOffset != 0) {
                    bucket.engineProfitOffset += profitOffset;
                    state.rollingEngineProfitOffset += profitOffset;
                }
            }

        }

        emit EngineRiskSettled(
            vault,
            msg.sender,
            reservedRisk,
            realizedLoss,
            profitOffset,
            state.activeEngineRiskReserve,
            _riskUsed(state),
            _riskRemaining(vault, state)
        );
    }

    function _recordGovernanceMovement(address vault, uint256 amount) private returns (uint256 remainingAfter) {
        _refreshRiskWindow(vault);
        remainingAfter = _consumeRiskCapacity(vault, amount);

        (, RiskBucket storage bucket) = _currentRiskBucket(vault);
        RiskState storage state = riskStates[vault];
        bucket.governanceMoved += amount;
        state.rollingGovernanceMoved += amount;
    }

    function _consumeRiskCapacity(address vault, uint256 amount) private view returns (uint256 remainingAfter) {
        uint256 limit = _riskLimit(vault);
        if (limit == 0) {
            revert DailyBudgetExceeded();
        }

        uint256 used = _riskUsed(riskStates[vault]);
        if (amount > limit || used > limit - amount) {
            revert DailyBudgetExceeded();
        }

        remainingAfter = limit - used - amount;
    }

    function _refreshRiskWindow(address vault) private {
        RiskState storage state = riskStates[vault];
        uint256 cutoff = block.timestamp > WINDOW_DURATION ? block.timestamp - WINDOW_DURATION : 0;

        for (uint8 i = 0; i < RISK_BUCKET_COUNT; i++) {
            RiskBucket storage bucket = state.buckets[i];
            if (bucket.startedAt != 0 && bucket.startedAt <= cutoff) {
                _subtractBucket(state, bucket);
                bucket.startedAt = 0;
                bucket.engineLoss = 0;
                bucket.engineProfitOffset = 0;
                bucket.governanceMoved = 0;
            }
        }
    }

    function _currentRiskBucket(address vault) private returns (uint8 bucketIndex, RiskBucket storage bucket) {
        uint256 bucketNumber = block.timestamp / RISK_BUCKET_DURATION;
        bucketIndex = uint8(bucketNumber % RISK_BUCKET_COUNT);
        uint64 startedAt = uint64(bucketNumber * RISK_BUCKET_DURATION);
        RiskState storage state = riskStates[vault];
        bucket = state.buckets[bucketIndex];

        if (bucket.startedAt != startedAt) {
            _subtractBucket(state, bucket);
            bucket.startedAt = startedAt;
            bucket.engineLoss = 0;
            bucket.engineProfitOffset = 0;
            bucket.governanceMoved = 0;

            emit WindowOpened(vault, startedAt, _riskLimit(vault));
        }
    }

    function _subtractBucket(RiskState storage state, RiskBucket storage bucket) private {
        if (bucket.engineLoss > state.rollingEngineLoss) {
            revert RiskStateInvariantBroken();
        }
        state.rollingEngineLoss -= bucket.engineLoss;

        if (bucket.engineProfitOffset > state.rollingEngineProfitOffset) {
            revert RiskStateInvariantBroken();
        }
        state.rollingEngineProfitOffset -= bucket.engineProfitOffset;

        if (bucket.governanceMoved > state.rollingGovernanceMoved) {
            revert RiskStateInvariantBroken();
        }
        state.rollingGovernanceMoved -= bucket.governanceMoved;
    }

    function _riskRemainingView(address vault) private view returns (uint256) {
        uint256 limit = _riskLimit(vault);
        (
            uint256 activeReserve,
            uint256 rollingEngineLoss,
            uint256 rollingEngineProfitOffset,
            uint256 rollingGovernanceMoved
        ) = _riskTotalsView(vault);
        uint256 used = activeReserve + _engineNetLoss(rollingEngineLoss, rollingEngineProfitOffset)
            + rollingGovernanceMoved;

        if (used >= limit) {
            return 0;
        }

        return limit - used;
    }

    function _riskTotalsView(address vault)
        private
        view
        returns (
            uint256 activeReserve,
            uint256 rollingEngineLoss,
            uint256 rollingEngineProfitOffset,
            uint256 rollingGovernanceMoved
        )
    {
        RiskState storage state = riskStates[vault];
        activeReserve = state.activeEngineRiskReserve;
        uint256 cutoff = block.timestamp > WINDOW_DURATION ? block.timestamp - WINDOW_DURATION : 0;

        for (uint8 i = 0; i < RISK_BUCKET_COUNT; i++) {
            RiskBucket storage bucket = state.buckets[i];
            if (bucket.startedAt != 0 && bucket.startedAt > cutoff) {
                rollingEngineLoss += bucket.engineLoss;
                rollingEngineProfitOffset += bucket.engineProfitOffset;
                rollingGovernanceMoved += bucket.governanceMoved;
            }
        }
    }

    function _riskUsed(RiskState storage state) private view returns (uint256) {
        return state.activeEngineRiskReserve + _engineNetLoss(state.rollingEngineLoss, state.rollingEngineProfitOffset)
            + state.rollingGovernanceMoved;
    }

    function _riskRemaining(address vault, RiskState storage state) private view returns (uint256) {
        uint256 limit = _riskLimit(vault);
        uint256 used = _riskUsed(state);
        if (used >= limit) {
            return 0;
        }

        return limit - used;
    }

    function _riskLimit(address vault) private view returns (uint256) {
        return (IPoolVault(vault).totalAssets() * dailyLimitBps) / BPS_DENOMINATOR;
    }

    function _engineNetLoss(uint256 rollingEngineLoss, uint256 rollingEngineProfitOffset)
        private
        pure
        returns (uint256)
    {
        if (rollingEngineProfitOffset >= rollingEngineLoss) {
            return 0;
        }

        return rollingEngineLoss - rollingEngineProfitOffset;
    }

    function _enforceVaultBusinessController(address vault) private view {
        if (vault == address(0)) {
            revert InvalidAddress();
        }
        if (IPoolVault(vault).businessController() != msg.sender) {
            revert OnlyVaultBusinessController();
        }
    }
}
