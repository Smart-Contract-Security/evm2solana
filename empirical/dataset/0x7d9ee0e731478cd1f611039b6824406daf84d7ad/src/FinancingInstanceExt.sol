// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PhaseScheduleLib} from "./lib/PhaseScheduleLib.sol";
import {FinancingDataStorage} from "./FinancingDataStorage.sol";
import {FinancingTypes} from "./FinancingTypes.sol";
import {BondingCurveMath} from "./lib/BondingCurveMath.sol";

/// @title FinancingInstanceExt — Extension contract for FinancingInstance
/// @notice Contains view functions, COO config functions, and ERC1155 implementation.
///         Called via delegatecall from FinancingInstance's fallback().
///         Shares the same storage layout as FinancingInstance.
contract FinancingInstanceExt is IERC1155MetadataURI, FinancingDataStorage {
    using PhaseScheduleLib for PhaseScheduleLib.Schedule;

    // ================================================================
    //  COO Configuration Functions
    // ================================================================

    function setUncheckFeeConfig(address recipient, uint256 feeRateWad) external onlyRole(COO_ROLE) {
        if (recipient == address(0)) revert InvalidReceiver();
        if (feeRateWad > WAD) revert InvalidRate();
        _protocolFeeRecipient = recipient;
        _uncheckFeeRateWad = feeRateWad;
        emit UncheckFeeConfigUpdated(recipient, feeRateWad);
    }

    function getUncheckFeeConfig() external view returns (address recipient, uint256 feeRateWad) {
        return (_protocolFeeRecipient, _uncheckFeeRateWad);
    }

    function setProtocolFeeRecipient(address recipient) external onlyRole(COO_ROLE) {
        if (recipient == address(0)) revert InvalidReceiver();
        _protocolFeeRecipient = recipient;
        emit ProtocolFeeRecipientUpdated(recipient);
    }

    function setTradeFeeConfig(uint256 buyFeeRateWad, uint256 sellFeeRateWad) external onlyRole(COO_ROLE) {
        if (buyFeeRateWad > WAD || sellFeeRateWad >= WAD) revert InvalidRate();
        _buyFeeRateWad = buyFeeRateWad;
        _sellFeeRateWad = sellFeeRateWad;
        emit TradeFeeConfigUpdated(buyFeeRateWad, sellFeeRateWad);
    }

    function getTradeFeeConfig() external view returns (uint256 buyFeeRateWad, uint256 sellFeeRateWad) {
        return (_buyFeeRateWad, _sellFeeRateWad);
    }

    function setCheckProfitFeeConfig(uint256 thresholdRateWad, uint256 feeRateWad) external onlyRole(COO_ROLE) {
        if (thresholdRateWad > WAD || feeRateWad > WAD) revert InvalidRate();
        _checkProfitFeeThresholdWad = thresholdRateWad;
        _checkProfitFeeRateWad = feeRateWad;
        emit CheckProfitFeeConfigUpdated(thresholdRateWad, feeRateWad);
    }

    function getCheckProfitFeeConfig() external view returns (uint256 thresholdRateWad, uint256 feeRateWad) {
        return (_checkProfitFeeThresholdWad, _checkProfitFeeRateWad);
    }

    function setScheduleExtensionFeeConfig(uint256 phase1FeeAmount, uint256 phase2FeeAmount)
        external
        onlyRole(COO_ROLE)
    {
        _phase1ExtensionFeeAmount = phase1FeeAmount;
        _phase2ExtensionFeeAmount = phase2FeeAmount;
        emit ScheduleExtensionFeeConfigUpdated(phase1FeeAmount, phase2FeeAmount);
    }

    function getScheduleExtensionFeeConfig() external view returns (uint256 phase1FeeAmount, uint256 phase2FeeAmount) {
        return (_phase1ExtensionFeeAmount, _phase2ExtensionFeeAmount);
    }

    function setProjectClearDelay(uint64 delaySeconds) external onlyRole(COO_ROLE) {
        if (delaySeconds > MAX_PROJECT_CLEAR_DELAY) revert InvalidDuration();
        _projectClearDelay = delaySeconds;
        emit ProjectClearDelayUpdated(delaySeconds);
    }

    function getProjectClearDelay() external view returns (uint64) {
        return _projectClearDelay;
    }

    function setProjectFinalizationDelay(uint64 delaySeconds) external onlyRole(COO_ROLE) {
        if (delaySeconds > MAX_PROJECT_FINALIZATION_DELAY) revert InvalidDuration();
        _projectFinalizationDelay = delaySeconds;
        emit ProjectFinalizationDelayUpdated(delaySeconds);
    }

    function getProjectFinalizationDelay() external view returns (uint64) {
        return _projectFinalizationDelay;
    }

    // ================================================================
    //  View / Preview Functions
    // ================================================================

    function getProtocolConfig() external view returns (FinancingTypes.ProtocolConfigView memory viewData) {
        viewData = FinancingTypes.ProtocolConfigView({
            protocolFeeRecipient: _protocolFeeRecipient,
            uncheckFeeRateWad: _uncheckFeeRateWad,
            buyFeeRateWad: _buyFeeRateWad,
            sellFeeRateWad: _sellFeeRateWad,
            checkProfitFeeThresholdWad: _checkProfitFeeThresholdWad,
            checkProfitFeeRateWad: _checkProfitFeeRateWad,
            phase1ExtensionFeeAmount: _phase1ExtensionFeeAmount,
            phase2ExtensionFeeAmount: _phase2ExtensionFeeAmount,
            projectClearDelay: _projectClearDelay,
            projectFinalizationDelay: _projectFinalizationDelay
        });
    }

    function previewProjectClear() external view returns (FinancingTypes.ProjectClearPreview memory) {
        return _previewProjectClear();
    }

    function previewProjectWithdraw() external view returns (FinancingTypes.ProjectWithdrawPreview memory preview) {
        PhaseScheduleLib.Stage stage = _currentStage();
        bool finalWithdrawWindow =
            stage == PhaseScheduleLib.Stage.PHASE_4 && _settlementState.projectCleared && _canProjectFinalize();
        uint256 cumulativeCap = _maxProjectWithdrawableCumulative();
        uint256 capRemaining;
        if (cumulativeCap > _saleState.projectWithdrawnAmount) {
            capRemaining = cumulativeCap - _saleState.projectWithdrawnAmount;
        }

        uint256 sellReserve = finalWithdrawWindow ? 0 : _reserveRequiredForSell();
        uint256 checkReserve = finalWithdrawWindow ? 0 : _reserveRequiredForCheckSettlement();
        uint256 totalReserve = sellReserve + checkReserve;
        uint256 paymentBalance = _paymentBalance();
        uint256 balanceAfterReserve;
        if (paymentBalance > totalReserve) {
            balanceAfterReserve = paymentBalance - totalReserve;
        }

        preview = FinancingTypes.ProjectWithdrawPreview({
            currentStage: stage,
            paymentBalance: paymentBalance,
            cumulativeCap: cumulativeCap,
            alreadyWithdrawn: _saleState.projectWithdrawnAmount,
            capRemaining: capRemaining,
            sellReserve: sellReserve,
            checkSettlementReserve: checkReserve,
            totalReserve: totalReserve,
            balanceAfterReserve: balanceAfterReserve,
            availableWithdrawable: _availableForProjectWithdraw(),
            fullyEscrowed: _isFullyEscrowed(),
            escrowWithdrawUnlocked: _isEscrowWithdrawUnlocked(),
            phase1SuccessEffective: _isPhase1SuccessEffective(),
            finalWithdrawWindow: finalWithdrawWindow,
            projectCanFinalize: _canProjectFinalize()
        });
    }

    function previewCheckSettlement(address account) external view returns (FinancingTypes.SettlementResult memory) {
        if (_isPhase1FailureEffective()) {
            return _previewSettlement(account);
        }
        if (!_checkState.checkSettlementOpened || !_settlementState.projectCleared) {
            return FinancingTypes.SettlementResult(0, 0, 0, 0, 0);
        }
        return _previewSettlement(account);
    }

    function maxProjectWithdrawable() external view returns (uint256) {
        return _maxProjectWithdrawableCumulative();
    }

    function availableForProjectWithdraw() external view returns (uint256) {
        return _availableForProjectWithdraw();
    }

    function reserveRequiredForSell() external view returns (uint256) {
        return _reserveRequiredForSell();
    }

    function reserveRequiredForCheckSettlement() external view returns (uint256) {
        return _reserveRequiredForCheckSettlement();
    }

    function getOrderView() external view returns (FinancingTypes.OrderView memory viewData) {
        (uint64 startAt, uint64 phase1End, uint64 phase2End, uint64 phase3End) = _phaseBounds();
        viewData = FinancingTypes.OrderView({
            order: _orderView(),
            currentStage: _currentStage(),
            startAt: startAt,
            phase1End: phase1End,
            phase2End: phase2End,
            phase3End: phase3End
        });
    }

    function getCompactOrderView() external view returns (FinancingTypes.FinancingOrderCompactView memory) {
        return _compactOrderView();
    }

    function getSettlementView() external view returns (FinancingTypes.FinancingOrderSettlementView memory) {
        return _settlementView();
    }

    function getOrderMeta() external view returns (FinancingTypes.FinancingOrderMeta memory) {
        return _meta;
    }

    function getOrderConfig() external view returns (FinancingTypes.FinancingConfig memory) {
        return _config;
    }

    function getSaleState() external view returns (FinancingTypes.SaleState memory) {
        return _saleState;
    }

    function getCheckState() external view returns (FinancingTypes.CheckState memory) {
        return _checkState;
    }

    function getEscrowState() external view returns (FinancingTypes.EscrowState memory) {
        return _escrowState;
    }

    function getSettlementState() external view returns (FinancingTypes.SettlementState memory) {
        return _settlementState;
    }

    function getCheckPosition(address account) external view returns (FinancingTypes.CheckPosition memory) {
        return _checkPositions[account];
    }

    function getBuyerPosition(address account) external view returns (FinancingTypes.BuyerPosition memory) {
        return _buyerPositions[account];
    }

    function getClaimHolderUnderlyingClaimed(address account) external view returns (uint256) {
        return _claimedUnderlyingByClaimHolder[account];
    }

    function getCurrentStage() external view returns (PhaseScheduleLib.Stage) {
        return _currentStage();
    }

    // ================================================================
    //  ERC1155 Implementation
    // ================================================================

    function shareClaimId() external view returns (uint256) {
        return _meta.orderId;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155).interfaceId || interfaceId == type(IERC1155MetadataURI).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function uri(uint256) public view returns (string memory) {
        return _shareClaimUri;
    }

    function balanceOf(address account, uint256 id) public view returns (uint256) {
        if (account == address(0)) revert InvalidReceiver();
        return _shareClaimBalances[id][account];
    }

    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        returns (uint256[] memory balances)
    {
        if (accounts.length != ids.length) revert InvalidOrderConfig();
        balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            balances[i] = balanceOf(accounts[i], ids[i]);
        }
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == msg.sender) revert SelfApproval();
        _shareClaimApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) external view returns (bool) {
        return _shareClaimApprovals[account][operator];
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external {
        if (from != msg.sender && !_shareClaimApprovals[from][msg.sender]) revert UnauthorizedOperator();
        _transferShareClaims(from, to, id, amount, true);
        _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        if (ids.length != amounts.length) revert InvalidOrderConfig();
        if (from != msg.sender && !_shareClaimApprovals[from][msg.sender]) revert UnauthorizedOperator();
        if (to == address(0)) revert InvalidReceiver();
        for (uint256 i = 0; i < ids.length; ++i) {
            _transferShareClaims(from, to, ids[i], amounts[i], false);
        }
        emit TransferBatch(msg.sender, from, to, ids, amounts);
        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    // ================================================================
    //  Internal Helpers (duplicated from FinancingInstance for delegatecall)
    // ================================================================

    function _isPhase1FailureEffective() internal view returns (bool) {
        if (_settlementState.phase1Failed) return true;
        if (_isPhase1SuccessEffective()) return false;
        (, uint64 phase1End,,) = _phaseBounds();
        return block.timestamp >= phase1End && _checkState.checkedPrincipal < _preFundingTarget();
    }

    function _isPhase1SuccessEffective() internal view returns (bool) {
        if (_settlementState.phase1TargetReached) return true;
        (, uint64 phase1End,,) = _phaseBounds();
        return block.timestamp >= phase1End && _checkState.checkedPrincipal >= _preFundingTarget();
    }

    function _previewProjectClear() internal view returns (FinancingTypes.ProjectClearPreview memory preview) {
        preview.paymentBalance = _paymentBalance();
        preview.checkedPrincipal = _checkState.checkedPrincipal;
        preview.principalSettlementPool = Math.min(preview.paymentBalance, preview.checkedPrincipal);
        uint256 remainingCash = preview.paymentBalance - preview.principalSettlementPool;

        preview.interestPool = Math.min(remainingCash, _interestAccruedAmount());
        remainingCash -= preview.interestPool;

        preview.grossProfitPool = Math.min(remainingCash, _saleProfitAmount());
        remainingCash -= preview.grossProfitPool;

        preview.checkProfitFeeAmount = _checkProfitProtocolFee(preview.grossProfitPool);
        preview.checkProfitPool = preview.grossProfitPool - preview.checkProfitFeeAmount;

        preview.principalShortfall = preview.checkedPrincipal - preview.principalSettlementPool;
        preview.debtSharesUsed = _debtSharesForRawAmount(preview.principalShortfall);
        uint256 unsoldEscrowShares = _config.totalCommittedShares - _saleState.soldShares;
        if (preview.debtSharesUsed > unsoldEscrowShares) {
            preview.debtSharesUsed = unsoldEscrowShares;
        }

        preview.debtCoverageAmount = _rawAmountAtMinPrice(preview.debtSharesUsed);
        if (preview.debtCoverageAmount > preview.principalShortfall) {
            preview.debtCoverageAmount = preview.principalShortfall;
        }

        preview.checkLossAmount = preview.principalShortfall - preview.debtCoverageAmount;
        preview.settlementReserve = preview.principalSettlementPool + preview.interestPool + preview.checkProfitPool;
        preview.projectRedeemableShares = unsoldEscrowShares - preview.debtSharesUsed;

        uint256 remainingTargetCapacity;
        if (_config.targetAmount > _saleState.projectWithdrawnAmount) {
            remainingTargetCapacity = _config.targetAmount - _saleState.projectWithdrawnAmount;
        }
        preview.finalProjectWithdrawableAmount = Math.min(remainingCash, remainingTargetCapacity);
    }

    function _previewSettlement(address account) internal view returns (FinancingTypes.SettlementResult memory result) {
        FinancingTypes.CheckPosition storage position = _checkPositions[account];
        if (position.settled) return result;
        if (position.principal == 0 || _checkState.checkedPrincipal == 0) return result;

        if (_isPhase1FailureEffective()) {
            result.principalReturn = position.principal;
            return result;
        }

        uint256 totalPrincipal = _checkState.checkedPrincipal;
        uint256 totalWeight = _checkState.checkedWeightShares;

        result.principalReturn = Math.mulDiv(_checkState.principalSettlementPool, position.principal, totalPrincipal);
        result.lossAmount = Math.mulDiv(_checkState.checkLossAmount, position.principal, totalPrincipal);
        result.debtShareAmount = Math.mulDiv(_escrowState.sharesUsedForDebt, position.principal, totalPrincipal);

        if (totalWeight > 0) {
            result.interestReward = Math.mulDiv(_checkState.interestPool, position.weightShares, totalWeight);
            result.profitReward = Math.mulDiv(_checkState.checkProfitPool, position.weightShares, totalWeight);
        }
    }

    function _maxProjectWithdrawableCumulative() internal view returns (uint256) {
        PhaseScheduleLib.Stage stage = _currentStage();

        if (stage == PhaseScheduleLib.Stage.PHASE_4 && _settlementState.projectCleared && _canProjectFinalize()) {
            return Math.min(
                _config.targetAmount,
                _saleState.projectWithdrawnAmount + _settlementState.projectFinalWithdrawableAmount
            );
        }

        if (!_isFullyEscrowed() || !_isEscrowWithdrawUnlocked() || !_isPhase1SuccessEffective()) {
            return _saleState.projectWithdrawnAmount;
        }

        if (stage == PhaseScheduleLib.Stage.PHASE_2) {
            uint256 checkPrincipalCap = _checkState.checkedPrincipal / 2;
            uint256 realTimeCap =
                Math.max(_preFundingTarget(), Math.min(Math.mulDiv(_config.targetAmount, 60, 100), checkPrincipalCap));
            return Math.max(_saleState.projectWithdrawnAmount, realTimeCap);
        }

        return _saleState.projectWithdrawnAmount;
    }

    function _availableForProjectWithdraw() internal view returns (uint256) {
        PhaseScheduleLib.Stage stage = _currentStage();

        if (stage == PhaseScheduleLib.Stage.PHASE_4 && _settlementState.projectCleared && _canProjectFinalize()) {
            return Math.min(_settlementState.projectFinalWithdrawableAmount, _paymentBalance());
        }

        if (!_isFullyEscrowed() || !_isPhase1SuccessEffective()) return 0;
        if (!_isEscrowWithdrawUnlocked()) return 0;

        if (stage == PhaseScheduleLib.Stage.PHASE_2) {
            uint256 cumulativeCap = _maxProjectWithdrawableCumulative();
            if (cumulativeCap <= _saleState.projectWithdrawnAmount) return 0;

            uint256 capRemaining = cumulativeCap - _saleState.projectWithdrawnAmount;
            uint256 reserve = _reserveRequiredForSell() + _reserveRequiredForCheckSettlement();
            uint256 balance = _paymentBalance();
            if (balance <= reserve) return 0;
            return Math.min(capRemaining, balance - reserve);
        }

        return 0;
    }

    function _reserveRequiredForSell() internal view returns (uint256) {
        if (_currentStage() != PhaseScheduleLib.Stage.PHASE_2) return 0;
        uint256 unmintedShares = _unmintedSoldShares();
        if (unmintedShares == 0) return 0;
        return BondingCurveMath.quoteSellExactSharesRaw(_curveParams(), _saleState.soldShares, unmintedShares);
    }

    function _reserveRequiredForCheckSettlement() internal view returns (uint256) {
        if (_settlementState.projectCleared) return _checkState.settlementReserve;
        return _saleProfitAmount() + _interestAccruedAmount();
    }

    function _checkProfitProtocolFee(uint256 grossProfitPool) internal view returns (uint256) {
        uint256 thresholdAmount = Math.mulDiv(_config.targetAmount, _checkProfitFeeThresholdWad, WAD);
        if (grossProfitPool < thresholdAmount) return 0;
        return Math.mulDiv(grossProfitPool, _checkProfitFeeRateWad, WAD);
    }

    function _rawAmountAtMinPrice(uint256 sharesAmount) internal view returns (uint256) {
        if (sharesAmount == 0) return 0;
        return Math.mulDiv(Math.mulDiv(_config.priceMinWad, sharesAmount, WAD), _config.paymentUnit, WAD);
    }

    function _debtSharesForRawAmount(uint256 rawAmount) internal view returns (uint256) {
        if (rawAmount == 0) return 0;
        uint256 pricePerWholeShareRaw = Math.mulDiv(_config.priceMinWad, _config.paymentUnit, WAD);
        if (pricePerWholeShareRaw == 0) return 0;
        return Math.ceilDiv(rawAmount * WAD, pricePerWholeShareRaw);
    }

    function _transferShareClaims(address from, address to, uint256 id, uint256 amount, bool emitSingle) internal {
        if (from == address(0) || to == address(0)) revert InvalidReceiver();
        if (id != _meta.orderId) revert InvalidOrderConfig();

        uint256 fromBalance = _shareClaimBalances[id][from];
        if (amount > fromBalance) revert InsufficientBuyerShares();

        _moveClaimedUnderlying(from, to, amount, fromBalance);

        _shareClaimBalances[id][from] = fromBalance - amount;
        _shareClaimBalances[id][to] += amount;
        if (emitSingle) {
            emit TransferSingle(msg.sender, from, to, id, amount);
        }
    }

    function _moveClaimedUnderlying(address from, address to, uint256 amount, uint256 fromBalance) internal {
        if (amount == 0) return;
        uint256 fromClaimed = _claimedUnderlyingByClaimHolder[from];
        if (fromClaimed == 0) return;
        uint256 claimedToMove = Math.mulDiv(fromClaimed, amount, fromBalance);
        _claimedUnderlyingByClaimHolder[from] = fromClaimed - claimedToMove;
        _claimedUnderlyingByClaimHolder[to] += claimedToMove;
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal {
        if (to.code.length == 0) return;
        bytes4 response = IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data);
        if (response != IERC1155Receiver.onERC1155Received.selector) revert TransfersDisabled();
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        if (to.code.length == 0) return;
        bytes4 response = IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data);
        if (response != IERC1155Receiver.onERC1155BatchReceived.selector) revert TransfersDisabled();
    }
}
