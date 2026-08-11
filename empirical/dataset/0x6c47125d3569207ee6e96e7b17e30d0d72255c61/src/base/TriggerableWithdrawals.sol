// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.9 <0.9.0;

import {ConstantLib} from "./ConstantLib.sol";

/// @title TriggerableWithdrawals - EIP-7002 withdrawal request library
/// @notice Encapsulates interaction with the EIP-7002 withdrawal request system contract,
///         supporting full exits and partial withdrawals for beacon chain validators.
library TriggerableWithdrawals {
    error WithdrawalFeeReadFailed();
    error WithdrawalFeeInvalidData();
    error WithdrawalRequestAdditionFailed(bytes callData);
    error NoWithdrawalRequests();
    error MalformedPubkeysArray();
    error PartialWithdrawalRequired(uint256 index);
    error MismatchedArrayLengths(uint256 keysCount, uint256 amountsCount);

    /// @notice Submit full exit requests for a batch of validators (amount=0 means full exit)
    /// @dev Iterates over each validator pubkey and calls the system contract with feePerRequest
    /// @param pubkeys Concatenated validator BLS public keys (48 bytes each)
    /// @param feePerRequest Fee in wei for each withdrawal request
    function addFullWithdrawalRequests(bytes calldata pubkeys, uint256 feePerRequest) internal {
        uint256 keysCount = _validateAndCountPubkeys(pubkeys);
        bytes memory callData = new bytes(ConstantLib.WITHDRAWAL_REQUEST_CALLDATA_LENGTH);
        for (uint256 i = 0; i < keysCount; i++) {
            _copyAmountWithPubkeyToMemory(callData, 0, pubkeys, i);
            (bool success,) = ConstantLib.WITHDRAWAL_REQUEST.call{value: feePerRequest}(callData);
            if (!success) revert WithdrawalRequestAdditionFailed(callData);
        }
    }

    /// @notice Submit partial withdrawal requests with specified amounts for a batch of validators
    /// @dev Each validator has a corresponding withdrawal amount in Gwei
    /// @param pubkeys Concatenated validator BLS public keys (48 bytes each)
    /// @param amounts Withdrawal amounts in Gwei for each validator (must match pubkey count)
    /// @param feePerRequest Fee in wei for each withdrawal request
    function addWithdrawalRequests(
        bytes calldata pubkeys,
        uint64[] calldata amounts,
        uint256 feePerRequest
    ) internal {
        uint256 keysCount = _validateAndCountPubkeys(pubkeys);
        if (keysCount != amounts.length) revert MismatchedArrayLengths(keysCount, amounts.length);
        bytes memory callData = new bytes(ConstantLib.WITHDRAWAL_REQUEST_CALLDATA_LENGTH);
        for (uint256 i = 0; i < keysCount; i++) {
            _copyAmountWithPubkeyToMemory(callData, amounts[i], pubkeys, i);
            (bool success,) = ConstantLib.WITHDRAWAL_REQUEST.call{value: feePerRequest}(callData);
            if (!success) revert WithdrawalRequestAdditionFailed(callData);
        }
    }

    /// @notice Submit a single partial withdrawal request for one validator
    /// @dev Constructs the 56-byte system contract calldata (48-byte pubkey + 8-byte amount)
    /// @param pubkey The 48-byte BLS public key of the validator
    /// @param amount Withdrawal amount in Gwei (must be > 0 for partial withdrawal)
    /// @param feePerRequest Fee in wei for the withdrawal request
    function addSingleWithdrawalRequest(
        bytes calldata pubkey,
        uint64 amount,
        uint256 feePerRequest
    ) internal {
        if (pubkey.length != ConstantLib.PUBLIC_KEY_LENGTH) revert MalformedPubkeysArray();
        bytes memory callData = new bytes(ConstantLib.WITHDRAWAL_REQUEST_CALLDATA_LENGTH);
        uint256 pubkeyLen = ConstantLib.PUBLIC_KEY_LENGTH;
        assembly {
            mstore(add(callData, 56), amount)
            calldatacopy(add(callData, 32), pubkey.offset, pubkeyLen)
        }
        (bool success,) = ConstantLib.WITHDRAWAL_REQUEST.call{value: feePerRequest}(callData);
        if (!success) revert WithdrawalRequestAdditionFailed(callData);
    }

    /// @notice Query the current fee required per withdrawal request
    /// @dev Calls the system contract via staticcall; fee varies with queue congestion
    /// @return Fee in wei for each withdrawal request
    function getWithdrawalRequestFee() internal view returns (uint256) {
        (bool success, bytes memory feeData) = ConstantLib.WITHDRAWAL_REQUEST.staticcall("");
        if (!success) revert WithdrawalFeeReadFailed();
        if (feeData.length != 32) revert WithdrawalFeeInvalidData();
        return abi.decode(feeData, (uint256));
    }

    /// @notice Copy a pubkey and amount into a memory buffer for the system contract call
    /// @dev Uses inline assembly for efficient memory operations
    /// @param target Target memory buffer (56 bytes)
    /// @param amount Withdrawal amount in Gwei (0 = full exit)
    /// @param pubkeys Source concatenated pubkey data
    /// @param keyIndex Index of the pubkey to copy
    function _copyAmountWithPubkeyToMemory(
        bytes memory target,
        uint64 amount,
        bytes calldata pubkeys,
        uint256 keyIndex
    ) private pure {
        uint256 pubkeyLen = ConstantLib.PUBLIC_KEY_LENGTH;
        assembly {
            mstore(add(target, 56), amount)
            calldatacopy(add(target, 32), add(pubkeys.offset, mul(keyIndex, pubkeyLen)), pubkeyLen)
        }
    }

    /// @notice Validate pubkey data format and return the number of keys
    /// @dev Pubkey data length must be a multiple of 48 with at least one key
    /// @param pubkeys Concatenated pubkey data
    /// @return Number of validator public keys
    function _validateAndCountPubkeys(bytes calldata pubkeys) private pure returns (uint256) {
        if (pubkeys.length % ConstantLib.PUBLIC_KEY_LENGTH != 0) revert MalformedPubkeysArray();
        uint256 keysCount = pubkeys.length / ConstantLib.PUBLIC_KEY_LENGTH;
        if (keysCount == 0) revert NoWithdrawalRequests();
        return keysCount;
    }
}
