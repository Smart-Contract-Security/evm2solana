// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CoreAccess } from "../base/CoreAccess.sol";
import { IRebalanceManager } from "../interfaces/IRebalanceManager.sol";
import { RebalanceBuy, RebalanceTrigger, OndoTarget } from "../interfaces/Types.sol";

/// @title RebalanceManager
/// @notice saves the rebalancing status, target position, and transaction verification data, but does not directly hold or transfer assets.
contract RebalanceManager is CoreAccess, IRebalanceManager {
    address public coreVault;
    address public usdc;
    uint256 public rebalanceNonce;
    uint256 public minPassiveRebalanceInterval;
    uint256 public lastPassiveRebalanceAt;
    bytes32 public activeRebalanceId;
    mapping(bytes32 => address[]) private _rebalanceExpectedBuyTokens;
    mapping(bytes32 => uint256[]) private _rebalanceExpectedMinAmounts;
    mapping(bytes32 => RebalanceTrigger) public rebalanceTrigger;
    //0=Manual rebalancing,1=Periodic rebalancing,2=Rebalancing following a risk event,3=Clearance Event
    // 3. Special circumstances
    mapping(bytes32 => uint8) public rebalanceRiskLevel;
    mapping(bytes32 => bytes32) public rebalanceReasonHash;
    mapping(bytes32 => bool) public settledGroup;
    mapping(bytes32 => OndoTarget[]) private _pendingOndoTargets;
    bool private _rebalanceManagerInitialized;

    modifier onlyCoreVault() {
        _onlyCoreVault();
        _;
    }

    constructor(address admin, address usdc_) CoreAccess(admin) {
        if (admin != address(0)) _initializeRebalanceManager(usdc_);
    }

    function initialize(address admin, address usdc_) external {
        _initializeCoreAccess(admin);
        _initializeRebalanceManager(usdc_);
    }

    function _initializeRebalanceManager(address usdc_) internal {
        require(!_rebalanceManagerInitialized, "RebalanceManager: initialized");
        require(usdc_ != address(0), "RebalanceManager: zero usdc");
        _rebalanceManagerInitialized = true;
        usdc = usdc_;
    }

    function setCoreVault(address coreVault_) external onlyAdmin {
        require(coreVault_ != address(0), "RebalanceManager: zero core");
        coreVault = coreVault_;
    }

    function setPassiveRebalanceInterval(uint256 interval) external onlyAdmin {
        minPassiveRebalanceInterval = interval;
    }

    function prepareActiveRebalance(
        uint256 sellCount,
        uint256 buyCount,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) external onlyCoreVault returns (bytes32 rbId) {
        require(activeRebalanceId == bytes32(0), "RebalanceManager: active");
        require(sellCount > 0 && buyCount > 0, "RebalanceManager: empty active");
        rbId = _newRebalanceId(sellCount, buyCount, RebalanceTrigger.Active);
        rebalanceTrigger[rbId] = RebalanceTrigger.Active;
        _saveExpectedBuys(rbId, buys);
        _validateTargets(targetTokens, targetWeights);
        activeRebalanceId = rbId;
    }

    function preparePassiveRebalance(
        uint256 sellCount,
        uint256 buyCount,
        RebalanceTrigger trigger,
        uint8 riskLevel,
        bytes32 reasonHash,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) external onlyCoreVault returns (bytes32 rbId) {
        require(activeRebalanceId == bytes32(0), "RebalanceManager: active");
        _validatePassive(targetTokens.length, targetWeights.length, trigger);
        rbId = _newRebalanceId(sellCount, buyCount, trigger);
        lastPassiveRebalanceAt = block.timestamp;
        rebalanceTrigger[rbId] = trigger;
        rebalanceRiskLevel[rbId] = riskLevel;
        rebalanceReasonHash[rbId] = reasonHash;
        _validateTargets(targetTokens, targetWeights);
        _saveExpectedBuys(rbId, buys);
        activeRebalanceId = rbId;
    }

    function validateRebalanceFilled(bytes32 rbId, address[] calldata tokens, uint256[] calldata amounts)
        external
        view
    {
        _validateRebalanceFilled(rbId, tokens, amounts);
    }

    function _validateRebalanceFilled(bytes32 rbId, address[] calldata tokens, uint256[] calldata amounts)
        internal
        view
    {
        address[] storage expectedTokens = _rebalanceExpectedBuyTokens[rbId];
        uint256[] storage expectedAmounts = _rebalanceExpectedMinAmounts[rbId];
        for (uint256 i; i < expectedTokens.length; ++i) {
            uint256 actualAmount;
            for (uint256 j; j < tokens.length; ++j) {
                if (tokens[j] == expectedTokens[i]) actualAmount += amounts[j];
            }
            require(actualAmount >= expectedAmounts[i], "RebalanceManager: partial fill");
        }
    }

    function settleRebalance(bytes32 rbId) external onlyCoreVault {
        _settleRebalanceInternal(rbId);
    }

    function settleRebalanceFailure(bytes32 rbId) external onlyCoreVault {
        _settleRebalanceFailureInternal(rbId);
    }

    function _settleRebalanceInternal(bytes32 rbId) internal {
        _clearExpectedBuys(rbId);
        activeRebalanceId = bytes32(0);
    }

    function _settleRebalanceFailureInternal(bytes32 rbId) internal {
        _clearExpectedBuys(rbId);
        activeRebalanceId = bytes32(0);
    }

    ///  ---------------------------Settlement Entry Points---------------------------------

    function settleRebalanceComplete(
        bytes32 rbId,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external onlyCoreVault {
        if (settledGroup[rbId]) return;
        require(tokens.length == amounts.length, "RebalanceManager: length mismatch");
        _validateRebalanceFilled(rbId, tokens, amounts);
        settledGroup[rbId] = true;
        _settleRebalanceInternal(rbId);
        // Note: pendingOndoTargets will be applied by CoreVault after this call
    }

    function settleRebalanceFailed(bytes32 rbId) external onlyCoreVault {
        if (settledGroup[rbId]) return;
        settledGroup[rbId] = true;
        _settleRebalanceFailureInternal(rbId);
        _clearPendingOndoTargets(rbId);
    }

    function isSettled(bytes32 rbId) external view returns (bool) {
        return settledGroup[rbId];
    }

    ///  ---------------------------Pending Ondo Targets Management---------------------------------

    function savePendingOndoTargets(
        bytes32 rbId,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) external onlyCoreVault {
        require(targetTokens.length == targetWeights.length, "RebalanceManager: length mismatch");
        delete _pendingOndoTargets[rbId];
        uint256 total;
        for (uint256 i; i < targetTokens.length; ++i) {
            require(targetTokens[i] != address(0), "RebalanceManager: zero target");
            require(targetWeights[i] <= type(uint16).max, "RebalanceManager: bad weight");
            for (uint256 j; j < i; ++j) {
                require(targetTokens[i] != targetTokens[j], "RebalanceManager: duplicate");
            }
            total += targetWeights[i];
            _pendingOndoTargets[rbId].push(OndoTarget({ token: targetTokens[i], bps: uint16(targetWeights[i]) }));
        }
        require(total == 10_000, "RebalanceManager: bad total");
    }

    function getPendingOndoTargets(bytes32 rbId) external view returns (OndoTarget[] memory) {
        return _pendingOndoTargets[rbId];
    }

    function clearPendingOndoTargets(bytes32 rbId) external onlyCoreVault {
        _clearPendingOndoTargets(rbId);
    }

    function _clearPendingOndoTargets(bytes32 rbId) internal {
        delete _pendingOndoTargets[rbId];
    }

    function _validatePassive(uint256 targetTokenLength, uint256 targetWeightLength, RebalanceTrigger trigger)
        internal
        view
    {
        require(
            trigger == RebalanceTrigger.PassivePeriodic || trigger == RebalanceTrigger.PassiveRiskEvent,
            "RebalanceManager: bad trigger"
        );
        require(targetTokenLength == targetWeightLength, "RebalanceManager: length mismatch");
        if (trigger == RebalanceTrigger.PassivePeriodic && minPassiveRebalanceInterval > 0) {
            require(
                block.timestamp >= lastPassiveRebalanceAt + minPassiveRebalanceInterval, "RebalanceManager: too soon"
            );
        }
    }

    function _newRebalanceId(uint256 sellCount, uint256 buyCount, RebalanceTrigger trigger) internal returns (bytes32) {
        return _rebalanceHash(coreVault, block.chainid, ++rebalanceNonce, sellCount, buyCount, trigger);
    }

    function _onlyCoreVault() internal view {
        require(msg.sender == coreVault, "RebalanceManager: not core");
    }

    function _rebalanceHash(
        address vault,
        uint256 chainId,
        uint256 nonce_,
        uint256 sellCount,
        uint256 buyCount,
        RebalanceTrigger trigger
    ) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, and(vault, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x20), chainId)
            mstore(add(ptr, 0x40), 0xe0)
            mstore(add(ptr, 0x60), nonce_)
            mstore(add(ptr, 0x80), sellCount)
            mstore(add(ptr, 0xa0), buyCount)
            mstore(add(ptr, 0xc0), trigger)
            mstore(add(ptr, 0xe0), 2)
            mstore(add(ptr, 0x100), shl(240, 0x5242))
            result := keccak256(ptr, 0x120)
        }
    }

    function _validateTargets(address[] calldata targetTokens, uint256[] calldata targetWeights) internal pure {
        require(targetTokens.length == targetWeights.length, "RebalanceManager: length mismatch");
        uint256 total;
        for (uint256 i; i < targetTokens.length; ++i) {
            require(targetTokens[i] != address(0), "RebalanceManager: zero target");
            for (uint256 j; j < i; ++j) {
                require(targetTokens[i] != targetTokens[j], "RebalanceManager: duplicate");
            }
            total += targetWeights[i];
        }
        require(total == 10_000, "RebalanceManager: bad weights");
    }

    function _saveExpectedBuys(bytes32 rbId, RebalanceBuy[] calldata buys) internal {
        for (uint256 i; i < buys.length; ++i) {
            require(buys[i].tokenIn != address(0), "RebalanceManager: zero buy tokenIn");
            require(buys[i].tokenOut != address(0), "RebalanceManager: zero buy tokenOut");
            require(buys[i].tokenIn == usdc, "RebalanceManager: buy tokenIn");
            require(buys[i].amountIn > 0, "RebalanceManager: zero amount");
            _rebalanceExpectedBuyTokens[rbId].push(buys[i].tokenOut);
            _rebalanceExpectedMinAmounts[rbId].push(buys[i].minAmountOut);
        }
    }

    function _clearExpectedBuys(bytes32 rbId) internal {
        delete _rebalanceExpectedBuyTokens[rbId];
        delete _rebalanceExpectedMinAmounts[rbId];
    }
}
