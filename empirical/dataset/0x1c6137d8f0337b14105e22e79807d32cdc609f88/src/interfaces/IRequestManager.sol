// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { RequestStatus } from "./Types.sol";

interface IRequestManager {
    struct RequestData {
        address owner;
        bool isDeposit;
        uint256 assets;
        uint256 shares;
        uint256 settledShares;
        uint256 refundAssets;
        uint256 navRound;
        uint256 totalAssetsSnapshot;
        uint256 supplySnapshot;
        RequestStatus status;
        bytes32 groupId;
    }

    struct DepositSettlement {
        address owner;
        uint256 spent;
        uint256 shares;
        uint256 refund;
    }

    struct RedeemSettlement {
        address owner;
        uint256 requestedShares;
        uint256 fulfilledShares;
        uint256 returnedShares;
        uint256 payout;
    }

    struct FailureSettlement {
        address owner;
        bool isDeposit;
        uint256 shares;
        uint256 refund;
    }

    function setCoreVault(address coreVault) external;
    function createDepositRequest(
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 navRound,
        uint256 totalAssetsSnapshot,
        uint256 supplySnapshot
    ) external returns (uint256 reqId);
    function createRedeemRequest(
        address owner,
        uint256 shares,
        uint256 navRound,
        uint256 totalAssetsSnapshot,
        uint256 supplySnapshot,
        uint256 expectedAssets
    ) external returns (uint256 reqId);
    function setGroupId(uint256 reqId, bytes32 groupId) external;
    function validateDepositRequest(bytes32 groupId, uint256 reqId) external view;
    function settleDepositRequest(uint256 reqId, uint256 refundUsdc)
        external
        returns (DepositSettlement memory result);
    function validateRedeemRequest(bytes32 groupId, uint256 reqId) external view returns (uint256 totalShares);
    function settleRedeemRequest(
        uint256 reqId,
        uint256 usdcReceived
    ) external returns (RedeemSettlement memory result);
    function settleFailure(bytes32 groupId, uint256 reqId, uint256 returnedUsdc)
        external
        returns (FailureSettlement memory result);

    // Settlement entry points (called by AssetCustodian via CoreVault)
    function settleDeposit(
        bytes32 groupId,
        uint256 reqId,
        uint256 refundUsdc
    ) external returns (DepositSettlement memory result);

    function settleRedeem(
        bytes32 groupId,
        uint256 reqId,
        uint256 usdcReceived
    ) external returns (RedeemSettlement memory result);

    function settleRequestFailure(
        bytes32 groupId,
        uint256 reqId,
        uint256 returnedUsdc
    ) external returns (FailureSettlement memory result);

    function isSettled(bytes32 groupId) external view returns (bool);

    function getRequest(uint256 reqId) external view returns (RequestData memory);
    function userRequestCount(address owner) external view returns (uint256);
    function userRequestIdAt(address owner, uint256 index) external view returns (uint256);
    function userEscrowedShares(address owner) external view returns (uint256);
    function escrowedShares() external view returns (uint256);
}
