// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { RebalanceBuy, RebalanceTrigger, OndoTarget } from "./Types.sol";

interface IRebalanceManager {
    function setCoreVault(address coreVault) external;
    function setPassiveRebalanceInterval(uint256 interval) external;
    function prepareActiveRebalance(
        uint256 sellCount,
        uint256 buyCount,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) external returns (bytes32 rbId);
    function preparePassiveRebalance(
        uint256 sellCount,
        uint256 buyCount,
        RebalanceTrigger trigger,
        uint8 riskLevel,
        bytes32 reasonHash,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) external returns (bytes32 rbId);
    function validateRebalanceFilled(bytes32 rbId, address[] calldata tokens, uint256[] calldata amounts) external view;

    // Settlement entry points (called by AssetCustodian via CoreVault)
    function settleRebalanceComplete(
        bytes32 rbId,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;

    function settleRebalanceFailed(bytes32 rbId) external;

    function isSettled(bytes32 rbId) external view returns (bool);

    // Pending Ondo Targets Management
    function savePendingOndoTargets(
        bytes32 rbId,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) external;

    function getPendingOndoTargets(bytes32 rbId) external view returns (OndoTarget[] memory);

    function clearPendingOndoTargets(bytes32 rbId) external;

    function activeRebalanceId() external view returns (bytes32);
    function rebalanceTrigger(bytes32 rbId) external view returns (RebalanceTrigger);
    function rebalanceRiskLevel(bytes32 rbId) external view returns (uint8);
    function rebalanceReasonHash(bytes32 rbId) external view returns (bytes32);
    function minPassiveRebalanceInterval() external view returns (uint256);
    function lastPassiveRebalanceAt() external view returns (uint256);
}
