import 'solana';

library Address {
    function isContract(address account) internal view returns (bool) {
        AccountInfo accountInfo = getAccountInfo(account);
        return accountInfo.owner == account;
    }

    function sendValue(address payable recipient, uint64 amount) internal {
        AccountInfo recipientInfo = getAccountInfo(recipient);
        require(recipientInfo.lamports >= amount, "Address: insufficient balance");

        recipientInfo.lamports += amount;
        tx.accounts.dataAccount.lamports -= amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint64 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        AccountInfo dataAccount = tx.accounts.dataAccount;
        require(dataAccount.lamports >= value, "Address: insufficient balance for call");

        AccountInfo targetInfo = getAccountInfo(target);
        targetInfo.lamports += value;
        dataAccount.lamports -= value;

        AccountMeta[4] memory metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: targetInfo.key, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        AccountMeta[4] memory metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: false}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: false}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        if (returndata.length > 0) {
            revert(errorMessage);
        } else {
            revert(errorMessage);
        }
    }

    function getAccountInfo(address account) private view returns (AccountInfo) {
        for (uint64 i = 0; i < tx.accounts.length; i++) {
            if (tx.accounts[i].key == account) {
                return tx.accounts[i];
            }
        }
        revert("Account not found");
    }
}