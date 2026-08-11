// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CoreAccess } from "../base/CoreAccess.sol";
import { IRequestManager } from "../interfaces/IRequestManager.sol";
import { RequestStatus } from "../interfaces/Types.sol";
import { FixedPoint } from "../libraries/FixedPoint.sol";

/// @title RequestManager
/// @notice Saves the status of users' asynchronous subscription/redemption orders, but does not hold any funds.
contract RequestManager is CoreAccess, IRequestManager {
    address public coreVault;
    uint256 public nextRequestId = 1;
    mapping(uint256 => RequestData) private _requests;
    mapping(address => uint256[]) private _userRequestIds;
    mapping(uint256 => uint256) public requestExpectedValue;
    mapping(address => uint256) public userEscrowedShares;
    uint256 public escrowedShares;
    mapping(bytes32 => bool) public settledGroup;
    bool private _requestManagerInitialized;

    modifier onlyCoreVault() {
        _onlyCoreVault();
        _;
    }

    constructor(address admin) CoreAccess(admin) { }

    function initialize(address admin) external {
        _initializeCoreAccess(admin);
        require(!_requestManagerInitialized, "RequestManager: initialized");
        _requestManagerInitialized = true;
        nextRequestId = 1;
    }

    function setCoreVault(address coreVault_) external onlyAdmin {
        require(coreVault_ != address(0), "RequestManager: zero core");
        coreVault = coreVault_;
    }

    ///  ---------------------------Order Creation---------------------------------

    function createDepositRequest(
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 navRound,
        uint256 totalAssetsSnapshot,
        uint256 supplySnapshot
    ) external onlyCoreVault returns (uint256 reqId) {
        reqId = nextRequestId++;
        _requests[reqId] = RequestData({
            owner: owner,
            isDeposit: true,
            assets: assets,
            shares: shares,
            settledShares: 0,
            refundAssets: 0,
            navRound: navRound,
            totalAssetsSnapshot: totalAssetsSnapshot,
            supplySnapshot: supplySnapshot,
            status: RequestStatus.Executing,
            groupId: bytes32(0)
        });
        _userRequestIds[owner].push(reqId);
    }


    function createRedeemRequest(
        address owner,
        uint256 shares,
        uint256 navRound,
        uint256 totalAssetsSnapshot,
        uint256 supplySnapshot,
        uint256 expectedAssets
    ) external onlyCoreVault returns (uint256 reqId) {
        reqId = nextRequestId++;
        _requests[reqId] = RequestData({
            owner: owner,
            isDeposit: false,
            assets: 0,
            shares: shares,
            settledShares: 0,
            refundAssets: 0,
            navRound: navRound,
            totalAssetsSnapshot: totalAssetsSnapshot,
            supplySnapshot: supplySnapshot,
            status: RequestStatus.Executing,
            groupId: bytes32(0)
        });
        requestExpectedValue[reqId] = expectedAssets;
        userEscrowedShares[owner] += shares;
        escrowedShares += shares;
        _userRequestIds[owner].push(reqId);
    }

    function setGroupId(uint256 reqId, bytes32 groupId) external onlyCoreVault {
        _requests[reqId].groupId = groupId;
    }

    ///  ---------------------------Order Settlement---------------------------------

    function validateDepositRequest(bytes32 groupId, uint256 reqId) external view {
        _validateDepositRequest(groupId, reqId);
    }

    function _validateDepositRequest(bytes32 groupId, uint256 reqId) internal view {
        RequestData storage r = _requests[reqId];
        require(r.status == RequestStatus.Executing && r.isDeposit, "RequestManager: bad deposit");
        require(r.groupId == groupId, "RequestManager: wrong group");
    }

    function _settleDepositRequest(uint256 reqId, uint256 refundUsdc)
        internal
        returns (DepositSettlement memory result)
    {
        RequestData storage r = _requests[reqId];
        require(refundUsdc <= r.assets, "RequestManager: refund high");
        uint256 spent = r.assets - refundUsdc;
        uint256 shares = _previewDeposit(FixedPoint.usdcToWad(r.assets), r.totalAssetsSnapshot, r.supplySnapshot);
        r.settledShares = shares;
        r.refundAssets = refundUsdc;
        r.status = RequestStatus.Completed;
        result = DepositSettlement({ owner: r.owner, spent: spent, shares: shares, refund: refundUsdc });
    }

    function validateRedeemRequest(bytes32 groupId, uint256 reqId)
        external
        view
        returns (uint256 totalShares)
    {
        return _validateRedeemRequest(groupId, reqId);
    }

    function _validateRedeemRequest(bytes32 groupId, uint256 reqId)
        internal
        view
        returns (uint256 totalShares)
    {
        RequestData storage r = _requests[reqId];
        require(r.status == RequestStatus.Executing && !r.isDeposit, "RequestManager: bad redeem");
        require(r.groupId == groupId, "RequestManager: wrong group");
        totalShares = r.shares;
    }

    function _settleRedeemRequest(
        uint256 reqId,
        uint256 usdcReceived
    ) internal returns (RedeemSettlement memory result) {
        RequestData storage r = _requests[reqId];
        uint256 fulfilledShares = r.shares;
        uint256 returnedShares = r.shares - fulfilledShares;
        r.status = RequestStatus.Completed;
        r.settledShares = r.shares;
        userEscrowedShares[r.owner] -= r.shares;
        escrowedShares -= r.shares;
        result = RedeemSettlement({
            owner: r.owner,
            requestedShares: r.shares,
            fulfilledShares: fulfilledShares,
            returnedShares: returnedShares,
            payout: usdcReceived
        });
    }

    function _settleFailure(bytes32 groupId, uint256 reqId, uint256 returnedUsdc)
        internal
        returns (FailureSettlement memory result)
    {
        RequestData storage r = _requests[reqId];
        require(r.status == RequestStatus.Executing, "RequestManager: bad fail");
        require(r.groupId == groupId, "RequestManager: wrong group");
        r.status = RequestStatus.Failed;
        if (r.isDeposit) {
            require(returnedUsdc <= r.assets, "RequestManager: refund high");
            r.refundAssets = returnedUsdc;
            result = FailureSettlement({ owner: r.owner, isDeposit: true, shares: 0, refund: returnedUsdc });
        } else {
            require(returnedUsdc == 0, "RequestManager: no usdc");
            userEscrowedShares[r.owner] -= r.shares;
            escrowedShares -= r.shares;
            result = FailureSettlement({ owner: r.owner, isDeposit: false, shares: r.shares, refund: 0 });
        }
    }

    ///  ---------------------------Settlement Entry Points---------------------------------

    function settleDeposit(
        bytes32 groupId,
        uint256 reqId,
        uint256 refundUsdc
    ) external onlyCoreVault returns (DepositSettlement memory result) {
        if (settledGroup[groupId]) return result;
        settledGroup[groupId] = true;
        _validateDepositRequest(groupId, reqId);
        result = _settleDepositRequest(reqId, refundUsdc);
    }

    function settleRedeem(
        bytes32 groupId,
        uint256 reqId,
        uint256 usdcReceived
    ) external onlyCoreVault returns (RedeemSettlement memory result) {
        if (settledGroup[groupId]) return result;
        settledGroup[groupId] = true;
        _validateRedeemRequest(groupId, reqId);
        result = _settleRedeemRequest(reqId, usdcReceived);
    }

    function settleRequestFailure(
        bytes32 groupId,
        uint256 reqId,
        uint256 returnedUsdc
    ) external onlyCoreVault returns (FailureSettlement memory result) {
        if (settledGroup[groupId]) return result;
        settledGroup[groupId] = true;
        result = _settleFailure(groupId, reqId, returnedUsdc);
    }

    function isSettled(bytes32 groupId) external view returns (bool) {
        return settledGroup[groupId];
    }


    ///  ---------------------------Public View---------------------------------

    function getRequest(uint256 reqId) external view returns (RequestData memory) {
        return _requests[reqId];
    }

    function userRequestCount(address owner) external view returns (uint256) {
        return _userRequestIds[owner].length;
    }

    function userRequestIdAt(address owner, uint256 index) external view returns (uint256) {
        return _userRequestIds[owner][index];
    }

    function _previewDeposit(uint256 assets18, uint256 totalAssets, uint256 supply) internal pure returns (uint256) {
        if (supply == 0 || totalAssets == 0) return assets18;
        return assets18 * supply / totalAssets;
    }

    function _onlyCoreVault() internal view {
        require(msg.sender == coreVault, "RequestManager: not core");
    }

}
