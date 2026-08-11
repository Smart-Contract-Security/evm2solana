// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { CoreAccess } from "../base/CoreAccess.sol";
import { Roles } from "../libraries/Roles.sol";
import { IACCallback } from "../interfaces/IACCallback.sol";
import { IAssetCustodian } from "../interfaces/IAssetCustodian.sol";
import { INAVOracle } from "../interfaces/INAVOracle.sol";
import { IOndoProxy } from "../interfaces/IOndoProxy.sol";
import { IVaultSettlement } from "../interfaces/IVaultSettlement.sol";
import { BatchHint, BatchStatus, RebalanceBuy, RebalanceTrigger, Trade } from "../interfaces/Types.sol";

interface ICoreVaultAllocation {
    function getTargetAllocation() external view returns (address[] memory tokens, uint256[] memory weights);
}

/// @title AssetCustodian
/// @notice Execution hub between CoreVault and external proxy: temporary fund/asset storage, routing policies, receiving proxy
contract AssetCustodian is
    CoreAccess,
    Pausable,
    ReentrancyGuard,
    IAssetCustodian,
    IACCallback
{
    using SafeERC20 for IERC20;

    enum Operation {
        Deposit,
        Redeem,
        Rebalance
    }

    struct GroupState {
        Operation op;
        BatchStatus status;
        uint256 reqId;
        uint256 inAmount;
        bytes32 rbId;
        uint256 traceCount;
        uint256 settledTraceCount;
        bool hasFailure;
        uint256 depositProxyTraceCount;
        uint256 depositProxySuccessCount;
        uint256 localDepositUsdcAmount;
        uint256 returnedUsdc;
        uint256 navRound;
        bytes routeData;
        bool dispatching;

        RebalanceBuy[] buyPlans;
        uint256 rebalanceUsdcProceeds;
        bool rebalanceBuyDispatched;
        BatchHint rebalanceHint;

        address[] settledTokens;
        uint256[] settledAmounts;
        bytes failReason;
        RebalanceTrigger rebalanceTrigger;
    }

    struct TraceState {
        bytes32 groupId;
        Operation op;
        address inputToken;
        address outputToken;
        uint256 minAmountOut;
        bool settled;
    }

    address public coreVault;
    IOndoProxy public ondoProxy;
    IERC20 public usdc;
    INAVOracle public navOracle;
    uint256 public nonce;
    uint256 internal constant MIN_PROXY_USDC_AMOUNT = 1e6;
    uint256 internal constant MIN_PROXY_ORDER_VALUE = 1e18;
    bool private _assetCustodianInitialized;

    mapping(bytes32 => GroupState) private _groups;
    mapping(uint256 => bytes32) public requestToGroup;
    mapping(bytes32 => TraceState) public traceState;

    event GroupCreated(bytes32 indexed groupId, Operation indexed op, uint256 requestCount);
    event TraceDispatched(
        bytes32 indexed groupId,
        bytes32 indexed traceId,
        Operation indexed op,
        address inputToken,
        address outputToken,
        uint256 amount
    );
    event TraceSettled(bytes32 indexed groupId, bytes32 indexed traceId, bool success, address token, uint256 amount);
    event ProxyCallbackFailed(bytes32 indexed groupId, bytes32 indexed traceId, Operation indexed op, bytes data);
    event GroupSettled(bytes32 indexed groupId, Operation indexed op);
    event GroupFailed(bytes32 indexed groupId, bytes reason);
    event RebalanceSnapshot(
        bytes32 indexed rbId,
        bytes32 indexed groupId,
        RebalanceTrigger indexed trigger,
        bool afterRebalance,
        bytes32 routeHash,
        bytes32 allocationHash,
        bytes routeData,
        address[] tokens,
        uint256[] amounts,
        uint256[] weights
    );
    event RebalanceLateCallbackIgnored(bytes32 indexed groupId, bytes32 indexed rbId);
    event OndoProxySet(address indexed proxy);

    modifier onlyCoreVault() {
        _onlyCoreVault();
        _;
    }

    modifier onlyOndoProxy() {
        _onlyOndoProxy();
        _;
    }

    constructor(
        address admin,
        address coreVault_,
        address ondoProxy_,
        address usdc_,
        address navOracle_
    ) CoreAccess(admin) {
        if (admin != address(0)) {
            _initializeAssetCustodian(coreVault_, ondoProxy_, usdc_, navOracle_);
        }
    }

    function initialize(
        address admin,
        address coreVault_,
        address ondoProxy_,
        address usdc_,
        address navOracle_
    ) external {
        _initializeCoreAccess(admin);
        _initializeAssetCustodian(coreVault_, ondoProxy_, usdc_, navOracle_);
    }

    function _initializeAssetCustodian(
        address coreVault_,
        address ondoProxy_,
        address usdc_,
        address navOracle_
    ) internal {
        require(!_assetCustodianInitialized, "AC:INIT");
        require(
            coreVault_ != address(0) && ondoProxy_ != address(0) && usdc_ != address(0) && navOracle_ != address(0),
            "AC: zero address"
        );
        _assetCustodianInitialized = true;
        coreVault = coreVault_;
        ondoProxy = IOndoProxy(ondoProxy_);
        usdc = IERC20(usdc_);
        navOracle = INAVOracle(navOracle_);
    }

    function setOndoProxy(address proxy) external onlyAdmin {
        require(proxy != address(0), "AC:ZP");
        ondoProxy = IOndoProxy(proxy);
        emit OndoProxySet(proxy);
    }

    function pause() external onlyRole(Roles.PAUSE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Roles.PAUSE_ROLE) {
        _unpause();
    }

    function groupState(bytes32 groupId) external view returns (Operation op, BatchStatus status, uint256 inAmount) {
        GroupState storage b = _groups[groupId];
        return (b.op, b.status, b.inAmount);
    }

    function groupReqId(bytes32 groupId) external view returns (uint256) {
        return _groups[groupId].reqId;
    }

    function groupTraceIds(bytes32 groupId) external view returns (bytes32[] memory) {
        GroupState storage b = _groups[groupId];
        bytes32[] memory ids = new bytes32[](b.traceCount);
        for (uint256 i; i < b.traceCount; ++i) {
            ids[i] = _traceId(groupId, i);
        }
        return ids;
    }

    function previewNextGroupId() external view returns (bytes32) {
        return _efficientHash(address(this), block.chainid, nonce + 1);
    }

    ///  ---------------------------Execution Function---------------------------------

    function executeDeposit(uint256 reqId, uint256 totalUsdc, BatchHint calldata hint)
        external
        onlyCoreVault
        whenNotPaused
        nonReentrant
        returns (bytes32 groupId)
    {
        require(reqId != 0 && totalUsdc > 0, "AC:ED");
        groupId = _newGroupId();
        GroupState storage b = _groups[groupId];
        b.op = Operation.Deposit;
        b.status = BatchStatus.PendingProxy;
        b.inAmount = totalUsdc;
        b.navRound = navOracle.latestRound();
        b.reqId = reqId;
        requestToGroup[reqId] = groupId;
        (address[] memory targetTokens, uint256[] memory bps) = ICoreVaultAllocation(coreVault).getTargetAllocation();
        require(targetTokens.length > 0 && targetTokens.length == bps.length, "AC:TA");
        uint256 totalBps;
        for (uint256 i; i < bps.length; ++i) {
            totalBps += bps[i];
        }
        require(totalBps == 10_000, "AC:BW");
        uint256 dispatched;
        b.dispatching = true;
        for (uint256 i; i < targetTokens.length; ++i) {
            uint256 orderAmount = i == targetTokens.length - 1 ? totalUsdc - dispatched : totalUsdc * bps[i] / 10_000;
            dispatched += orderAmount;
            if (orderAmount == 0) continue;
            _dispatchProxyOrder(groupId, Operation.Deposit, address(usdc), targetTokens[i], orderAmount, 0, hint);
        }
        require(b.traceCount > 0, "AC:NT");
        b.dispatching = false;
        emit GroupCreated(groupId, Operation.Deposit, 1);
        _finalizeIfReady(groupId, b);
    }

    function executeRedeem(
        uint256 reqId,
        address[] calldata etfTokens,
        uint256[] calldata amounts,
        BatchHint calldata hint
    ) external onlyCoreVault whenNotPaused nonReentrant returns (bytes32 groupId) {
        require(reqId != 0, "AC:ER");
        require(etfTokens.length == amounts.length, "AC:LEN");
        groupId = _newGroupId();
        GroupState storage b = _groups[groupId];
        b.op = Operation.Redeem;
        b.status = BatchStatus.PendingProxy;
        b.navRound = navOracle.latestRound();
        b.reqId = reqId;
        requestToGroup[reqId] = groupId;
        b.dispatching = true;
        for (uint256 i; i < etfTokens.length; ++i) {
            if (amounts[i] == 0) continue;
            _dispatchProxyOrder(groupId, Operation.Redeem, etfTokens[i], address(usdc), amounts[i], 0, hint);
        }
        require(b.traceCount > 0, "AC:NT");
        b.dispatching = false;
        emit GroupCreated(groupId, Operation.Redeem, 1);
        _finalizeIfReady(groupId, b);
    }

    function executeRebalance(
        bytes32 rbId,
        Trade[] calldata sells,
        RebalanceBuy[] calldata buys,
        RebalanceTrigger trigger,
        BatchHint calldata hint
    ) external onlyCoreVault whenNotPaused nonReentrant returns (bytes32 groupId) {
        groupId = _newGroupId();
        GroupState storage b = _groups[groupId];
        b.op = Operation.Rebalance;
        b.status = BatchStatus.PendingProxy;
        b.rbId = rbId;
        b.rebalanceHint = hint;
        b.navRound = navOracle.latestRound();
        b.rebalanceTrigger = trigger;
        _copyRebalanceBuyPlans(b, buys);
        b.routeData = abi.encode(sells, buys);
        _emitRebalanceSnapshot(groupId, rbId, trigger, false, b.routeData);
        b.dispatching = true;
        for (uint256 i; i < sells.length; ++i) {
            if (sells[i].amountIn == 0) continue;
            require(sells[i].tokenOut == address(usdc), "AC:SU");
            _dispatchProxyOrder(
                groupId,
                Operation.Rebalance,
                sells[i].tokenIn,
                address(usdc),
                sells[i].amountIn,
                sells[i].minAmountOut,
                hint
            );
        }
        require(b.traceCount > 0, "AC:NT");
        b.dispatching = false;
        emit GroupCreated(groupId, Operation.Rebalance, 0);
        _finalizeIfReady(groupId, b);
    }

    function _dispatchProxyOrder(
        bytes32 groupId,
        Operation op,
        address inputToken,
        address outputToken,
        uint256 amount,
        uint256 minAmountOut,
        BatchHint memory hint
    ) internal {
        uint256 traceIndex = _groups[groupId].traceCount;
        bytes32 traceId = _traceId(groupId, traceIndex);
        traceState[traceId] = TraceState({
            groupId: groupId,
            op: op,
            inputToken: inputToken,
            outputToken: outputToken,
            minAmountOut: minAmountOut,
            settled: false
        });
        _groups[groupId].traceCount += 1;
        if (inputToken == outputToken) {
            // Intercept sub-orders locally
            emit TraceDispatched(groupId, traceId, op, inputToken, outputToken, amount);
            _onLocalTraceSettled(traceId, outputToken, amount);
            return;
        }
        if (op == Operation.Deposit) {
            _groups[groupId].depositProxyTraceCount += 1;
        }
        _validateMinProxyOrder(inputToken, amount);

        bytes memory extraData = abi.encode(inputToken, outputToken, amount);
        IOndoProxy.DepositIntent memory intent = IOndoProxy.DepositIntent({
            receiver: address(this),
            outputToken: outputToken,
            destinationChainId: block.chainid,
            maxSlippageBps: hint.maxSlippageBps,
            maxLossPercentBps: hint.maxLossPercentBps,
            extraData: extraData
        });
        IERC20(inputToken).forceApprove(address(ondoProxy), amount);
        ondoProxy.depositERC20(inputToken, amount, traceId, intent);
        IERC20(inputToken).forceApprove(address(ondoProxy), 0);

        emit TraceDispatched(groupId, traceId, op, inputToken, outputToken, amount);
    }

    function _onLocalTraceSettled(bytes32 traceId, address outputToken, uint256 amount) internal {
        TraceState storage t = traceState[traceId];
        GroupState storage b = _groups[t.groupId];
        t.settled = true;
        b.settledTraceCount += 1;
        uint256 actual = _recordSuccessfulTrace(t.groupId, b, t, outputToken, amount);
        if (t.op == Operation.Deposit && outputToken == address(usdc)) {
            b.localDepositUsdcAmount += actual;
        }
        emit TraceSettled(t.groupId, traceId, true, outputToken, amount);
        _finalizeIfReady(t.groupId, b);
    }


    ///  ---------------------------Callback Function---------------------------------

    /// @notice Proxy Single trace order settlement callback. AC aggregates the results of all traces within the group, and notifies CoreVault for final settlement only after all callbacks are completed.
    function onOrderSettled(bytes32 traceId, bool success, address token, uint256 amount, bytes calldata data)
        external
        onlyOndoProxy
        nonReentrant
    {
        TraceState storage t = traceState[traceId];
        bytes32 groupId = t.groupId;
        require(groupId != bytes32(0), "AC:UT");
        require(!t.settled, "AC:TS");
        GroupState storage b = _groups[groupId];

        if (b.status == BatchStatus.Settled || b.status == BatchStatus.Failed) {
            _forwardLateAssetToCore(token, amount);
            if (b.op == Operation.Rebalance) emit RebalanceLateCallbackIgnored(groupId, b.rbId);
            return;
        }

        require(b.status == BatchStatus.PendingProxy && b.op == t.op, "AC:BTC");
        t.settled = true;
        b.settledTraceCount += 1;
        if (success) {
            uint256 actual = _recordSuccessfulTrace(groupId, b, t, token, amount);
            if (t.op == Operation.Deposit && actual > 0) {
                b.depositProxySuccessCount += 1;
            }
        } else {
            emit ProxyCallbackFailed(groupId, traceId, t.op, data);
            if (data.length != 0 && b.failReason.length == 0) b.failReason = data;
            _recordFailedTrace(groupId, b, t, token, amount);
        }

        emit TraceSettled(groupId, traceId, success, token, amount);

        _finalizeIfReady(groupId, b);
    }

    function _finalizeIfReady(bytes32 groupId, GroupState storage b) internal {
        if (b.dispatching || b.settledTraceCount != b.traceCount) return;
        if (b.op == Operation.Rebalance && !b.rebalanceBuyDispatched) {
            _finalizeRebalanceSellPhase(groupId, b);
        } else {
            _finalizeGroup(groupId, b);
        }
    }

    function _recordSuccessfulTrace(
        bytes32 groupId,
        GroupState storage b,
        TraceState storage t,
        address token,
        uint256 amount
    ) internal returns (uint256 actual) {
        if (t.minAmountOut > 0) require(amount >= t.minAmountOut, "AC:UF");
        if (t.op == Operation.Deposit) {
            require(token == t.outputToken, "AC:BDT");
            actual = amount;
            _appendSettledToken(b, token, actual);
        } else if (t.op == Operation.Redeem) {
            require(token == address(usdc), "AC:BRT");
            b.returnedUsdc += amount;
            actual = amount;
        } else if (t.op == Operation.Rebalance) {
            require(token == t.outputToken, "AC:BBT");
            if (!b.rebalanceBuyDispatched) {
                require(token == address(usdc), "AC:BSO");
                b.rebalanceUsdcProceeds += amount;
                actual = amount;
            } else {
                actual = _safeTransferToCoreByBalanceDiff(token, amount);
                _appendSettledToken(b, token, actual);
            }
        }
    }

    function _recordFailedTrace(
        bytes32 groupId,
        GroupState storage b,
        TraceState storage t,
        address token,
        uint256 amount
    ) internal {
        b.hasFailure = true;
        if (b.failReason.length == 0) b.failReason = bytes("AC: proxy order failed");
        if (t.op == Operation.Deposit) {
            require(token == address(usdc), "AC:BDR");
            b.returnedUsdc += amount;
        } else if (t.op == Operation.Redeem) {
            require(token == t.inputToken, "AC:BRR");
            _returnSingleUnsoldToken(token, amount);
        } else if (t.op == Operation.Rebalance) {
            require(token == t.inputToken || token == t.outputToken, "AC:BRF");
            if (token == address(usdc)) {
                b.rebalanceUsdcProceeds += amount;
            } else {
                _forwardLateAssetToCore(token, amount);
            }
        }
    }

    function _finalizeRebalanceSellPhase(bytes32 groupId, GroupState storage b) internal {
        if (b.hasFailure) {
            _flushRebalanceUsdcToCore(b);
            b.status = BatchStatus.Failed;
            IVaultSettlement(coreVault).settleRebalanceFailure(b.rbId, b.failReason);
            emit GroupFailed(groupId, b.failReason);
            return;
        }
        if (b.rebalanceUsdcProceeds == 0) {
            b.status = BatchStatus.Failed;
            b.failReason = bytes("AC: no sell proceeds");
            IVaultSettlement(coreVault).settleRebalanceFailure(b.rbId, b.failReason);
            emit GroupFailed(groupId, b.failReason);
            return;
        }
        b.rebalanceBuyDispatched = true;
        uint256 beforeTraceCount = b.traceCount;
        uint256 totalProceeds = b.rebalanceUsdcProceeds;
        BatchHint memory hint = _rebalanceHint(b);
        uint256 totalRequestedAmountIn;
        for (uint256 i; i < b.buyPlans.length; ++i) {
            require(b.buyPlans[i].amountIn > 0, "AC:ZBA");
            totalRequestedAmountIn += b.buyPlans[i].amountIn;
        }
        require(totalRequestedAmountIn > 0, "AC:ZTA");
        uint256 dispatchedUsdc;
        b.dispatching = true;
        for (uint256 i; i < b.buyPlans.length; ++i) {
            uint256 orderAmount;
            if (i < b.buyPlans.length - 1) {
                orderAmount = totalProceeds * b.buyPlans[i].amountIn / totalRequestedAmountIn;
            } else {
                orderAmount = totalProceeds - dispatchedUsdc;
            }
            require(orderAmount > 0, "AC:ZBA");
            dispatchedUsdc += orderAmount;
            b.rebalanceUsdcProceeds -= orderAmount;
            _dispatchProxyOrder(
                groupId,
                Operation.Rebalance,
                b.buyPlans[i].tokenIn,
                b.buyPlans[i].tokenOut,
                orderAmount,
                b.buyPlans[i].minAmountOut,
                hint
            );
        }
        b.dispatching = false;
        require(b.traceCount > beforeTraceCount, "AC:NBT");
        _finalizeIfReady(groupId, b);
    }

    function _finalizeGroup(bytes32 groupId, GroupState storage b)
        internal
    {
        if (b.op == Operation.Deposit) {
            _finalizeDepositGroup(groupId, b);
        } else if (b.op == Operation.Redeem) {
            _finalizeRedeemGroup(groupId, b);
        } else if (b.op == Operation.Rebalance) {
            _finalizeRebalanceGroup(groupId, b);
        }
    }

    function _finalizeDepositGroup(bytes32 groupId, GroupState storage b) internal {
        if (b.returnedUsdc > 0) usdc.safeTransfer(coreVault, b.returnedUsdc);
        if (b.depositProxyTraceCount > 0 && b.depositProxySuccessCount == 0) {
            _transferSettledAssetsToCore(b);
            uint256 refundUsdc = b.returnedUsdc + b.localDepositUsdcAmount;
            b.status = BatchStatus.Failed;
            if (b.failReason.length == 0) b.failReason = bytes("AC: no proxy deposit fills");
            IVaultSettlement(coreVault).settleFailure(groupId, b.reqId, refundUsdc, b.failReason);
            emit GroupFailed(groupId, b.failReason);
            return;
        }
        if (b.settledTokens.length == 0) {
            b.status = BatchStatus.Failed;
            IVaultSettlement(coreVault).settleFailure(groupId, b.reqId, b.returnedUsdc, b.failReason);
            emit GroupFailed(groupId, b.failReason);
            return;
        }
        require(b.navRound != 0, "AC:MNR");
        _transferSettledAssetsToCore(b);
        b.status = BatchStatus.Settled;
        IVaultSettlement(coreVault)
            .settleDeposit(groupId, b.reqId, b.settledTokens, b.settledAmounts, b.returnedUsdc, b.navRound);
        emit GroupSettled(groupId, Operation.Deposit);
    }

    function _finalizeRedeemGroup(bytes32 groupId, GroupState storage b) internal {
        if (b.returnedUsdc > 0) usdc.safeTransfer(coreVault, b.returnedUsdc);
        if (b.hasFailure || b.returnedUsdc == 0) {
            b.status = BatchStatus.Failed;
            IVaultSettlement(coreVault).settleFailure(groupId, b.reqId, 0, b.failReason);
            emit GroupFailed(groupId, b.failReason);
            return;
        }
        require(b.navRound != 0, "AC:MNR");
        b.status = BatchStatus.Settled;
        IVaultSettlement(coreVault).settleRedeem(groupId, b.reqId, b.returnedUsdc, b.navRound);
        emit GroupSettled(groupId, Operation.Redeem);
    }

    function _finalizeRebalanceGroup(
        bytes32 groupId,
        GroupState storage b
    ) internal {
        if (b.hasFailure) {
            _flushRebalanceUsdcToCore(b);
            b.status = BatchStatus.Failed;
            IVaultSettlement(coreVault).settleRebalanceFailure(b.rbId, b.failReason);
            emit GroupFailed(groupId, b.failReason);
            return;
        }
        require(b.rebalanceBuyDispatched, "AC:BND");
        _flushRebalanceUsdcToCore(b);
        b.status = BatchStatus.Settled;
        IVaultSettlement(coreVault)
            .settleRebalance(b.rbId, b.settledTokens, b.settledAmounts);
        _emitRebalanceSnapshot(groupId, b.rbId, b.rebalanceTrigger, true, b.routeData);
        emit GroupSettled(groupId, Operation.Rebalance);
    }



    function _appendSettledToken(GroupState storage b, address token, uint256 amount) internal {
        if (amount == 0) return;
        b.settledTokens.push(token);
        b.settledAmounts.push(amount);
    }

    function _transferSettledAssetsToCore(GroupState storage b) internal {
        for (uint256 i; i < b.settledTokens.length; ++i) {
            uint256 amount = b.settledAmounts[i];
            if (amount == 0) continue;
            IERC20(b.settledTokens[i]).safeTransfer(coreVault, amount);
        }
    }

    function _safeTransferToCoreByBalanceDiff(address token, uint256 amount) internal returns (uint256 actual) {
        if (amount == 0) return 0;
        uint256 beforeBalance = IERC20(token).balanceOf(coreVault);
        IERC20(token).safeTransfer(coreVault, amount);
        actual = IERC20(token).balanceOf(coreVault) - beforeBalance;
    }

    function _forwardLateAssetToCore(address token, uint256 amount) internal {
        if (amount > 0) IERC20(token).safeTransfer(coreVault, amount);
    }

    function _returnSingleUnsoldToken(address token, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).safeTransfer(coreVault, amount);
    }

    function _newGroupId() internal returns (bytes32) {
        uint256 nextNonce = ++nonce;
        return _efficientHash(address(this), block.chainid, nextNonce);
    }

    function _traceId(bytes32 groupId, uint256 traceIndex) internal view returns (bytes32) {
        return _efficientHash(address(this), block.chainid, groupId, traceIndex);
    }

    function _onlyCoreVault() internal view {
        require(msg.sender == coreVault, "AC:NC");
    }

    function _onlyOndoProxy() internal view {
        require(msg.sender == address(ondoProxy), "AC:NP");
    }

    function _efficientHash(address account, uint256 chainId, uint256 value) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, and(account, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x20), chainId)
            mstore(add(ptr, 0x40), value)
            result := keccak256(ptr, 0x60)
        }
    }

    function _efficientHash(
        address account,
        uint256 chainId,
        bytes32 groupId,
        uint256 traceIndex
    ) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, and(account, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x20), chainId)
            mstore(add(ptr, 0x40), groupId)
            mstore(add(ptr, 0x60), traceIndex)
            result := keccak256(ptr, 0x80)
        }
    }

    function _copyRebalanceBuyPlans(GroupState storage b, RebalanceBuy[] calldata buys) internal {
        require(buys.length > 0, "AC:EB");
        for (uint256 i; i < buys.length; ++i) {
            require(buys[i].tokenIn != address(0), "AC:ZBI");
            require(buys[i].tokenOut != address(0), "AC:ZBT");
            require(buys[i].tokenIn == address(usdc), "AC:BUI");
            require(buys[i].amountIn > 0, "AC:ZBA");
            b.buyPlans.push(buys[i]);
        }
    }

    function _rebalanceHint(GroupState storage b) internal view returns (BatchHint memory) {
        return b.rebalanceHint;
    }

    function _emitRebalanceSnapshot(
        bytes32 groupId,
        bytes32 rbId,
        RebalanceTrigger trigger,
        bool afterRebalance,
        bytes memory routeData
    ) internal {
        (
            address[] memory tokens,
            uint256[] memory amounts,
            uint256[] memory weights,
            bytes32 allocationHash
        ) = _rebalanceSnapshotData();
        emit RebalanceSnapshot({
            rbId: rbId,
            groupId: groupId,
            trigger: trigger,
            afterRebalance: afterRebalance,
            routeHash: keccak256(routeData),
            allocationHash: allocationHash,
            routeData: routeData,
            tokens: tokens,
            amounts: amounts,
            weights: weights
        });
    }

    function _rebalanceSnapshotData()
        internal
        view
        returns (address[] memory tokens, uint256[] memory amounts, uint256[] memory weights, bytes32 allocationHash)
    {
        (tokens, weights) = ICoreVaultAllocation(coreVault).getTargetAllocation();
        amounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20 token = IERC20(tokens[i]);
            amounts[i] = token.balanceOf(coreVault) + token.balanceOf(address(this));
        }
        allocationHash = keccak256(abi.encode(tokens, amounts, weights));
    }

    function _flushRebalanceUsdcToCore(GroupState storage b) internal {
        uint256 bal = usdc.balanceOf(address(this));
        if (bal == 0) return;
        uint256 amount = bal < b.rebalanceUsdcProceeds ? bal : b.rebalanceUsdcProceeds;
        if (amount > 0) {
            b.rebalanceUsdcProceeds -= amount;
            usdc.safeTransfer(coreVault, amount);
        }
    }

    function _validateMinProxyOrder(address inputToken, uint256 amount) internal view {
        if (inputToken == address(usdc)) {
            require(amount >= MIN_PROXY_USDC_AMOUNT, "AC:MIN");
            return;
        }
        uint256 price = navOracle.priceOf(inputToken);
        require(amount * price / _assetUnit(inputToken) >= MIN_PROXY_ORDER_VALUE, "AC:MIN");
    }

    function _assetUnit(address token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= 36, "AC:DEC");
        return 10 ** uint256(decimals);
    }
}
