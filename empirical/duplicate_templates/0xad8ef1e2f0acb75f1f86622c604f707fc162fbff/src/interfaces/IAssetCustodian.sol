// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BatchHint, RebalanceBuy, RebalanceTrigger, Trade } from "./Types.sol";

interface IAssetCustodian {
    function previewNextGroupId() external view returns (bytes32);

    function executeDeposit(uint256 reqId, uint256 totalUsdc, BatchHint calldata hint)
        external
        returns (bytes32 groupId);

    function executeRedeem(
        uint256 reqId,
        address[] calldata etfTokens,
        uint256[] calldata amounts,
        BatchHint calldata hint
    ) external returns (bytes32 groupId);

    function executeRebalance(
        bytes32 rbId,
        Trade[] calldata sells,
        RebalanceBuy[] calldata buys,
        RebalanceTrigger trigger,
        BatchHint calldata hint
    ) external returns (bytes32 groupId);

}
