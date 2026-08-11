// SPDX-License-Identifier: MIT

// Define the types locally since they cannot be imported from another file
enum RebalanceBuy {
    None,
    Buy,
    Sell
}

enum RebalanceTrigger {
    None,
    Active,
    Passive
}

struct OndoTarget {
    address token;
    uint64 weight;
}

interface IRebalanceManager {
    function setCoreVault(address coreVault) external;
    function setPassiveRebalanceInterval(uint64 interval) external;
    function prepareActiveRebalance(
        uint64 sellCount,
        uint64 buyCount,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint64[] calldata targetWeights
    ) external returns (bytes32 rbId);
    function preparePassiveRebalance(
        uint64 sellCount,
        uint64 buyCount,
        RebalanceTrigger trigger,
        uint8 riskLevel,
        bytes32 reasonHash,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint64[] calldata targetWeights
    ) external returns (bytes32 rbId);
    function validateRebalanceFilled(bytes32 rbId, address[] calldata tokens, uint64[] calldata amounts) external view;

    // Settlement entry points (called by AssetCustodian via CoreVault)
    function settleRebalanceComplete(
        bytes32 rbId,
        address[] calldata tokens,
        uint64[] calldata amounts
    ) external;

    function settleRebalanceFailed(bytes32 rbId) external;

    function isSettled(bytes32 rbId) external view returns (bool);

    // Pending Ondo Targets Management
    function savePendingOndoTargets(
        bytes32 rbId,
        address[] calldata targetTokens,
        uint64[] calldata targetWeights
    ) external;

    function getPendingOndoTargets(bytes32 rbId) external view returns (OndoTarget[] memory);

    function clearPendingOndoTargets(bytes32 rbId) external;

    function activeRebalanceId() external view returns (bytes32);
    function rebalanceTrigger(bytes32 rbId) external view returns (RebalanceTrigger);
    function rebalanceRiskLevel(bytes32 rbId) external view returns (uint8);
    function rebalanceReasonHash(bytes32 rbId) external view returns (bytes32);
    function minPassiveRebalanceInterval() external view returns (uint64);
    function lastPassiveRebalanceAt() external view returns (uint64);
}