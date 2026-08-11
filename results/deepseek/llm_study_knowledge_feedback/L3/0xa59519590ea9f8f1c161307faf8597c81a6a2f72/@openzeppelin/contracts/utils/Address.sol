import 'solana';

library Address {
    function sendValue(address payable recipient, uint64 amount) internal {
        AccountInfo memory selfInfo = tx.accounts[address(this)];
        if (selfInfo.lamports < amount) {
            revert("Address: insufficient balance");
        }

        AccountInfo memory recipientInfo = tx.accounts[recipient];
        recipientInfo.lamports += amount;
        selfInfo.lamports -= amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        AccountInfo memory selfInfo = tx.accounts[address(this)];
        if (selfInfo.lamports < value) {
            revert("Address: insufficient balance");
        }

        AccountInfo memory targetInfo = tx.accounts[target];
        targetInfo.lamports += value;
        selfInfo.lamports -= value;

        AccountMeta[4] memory metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: true}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: false})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            if (returndata.length == 0) {
                revert("Address: empty code");
            }
            return returndata;
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    function _revert(bytes memory returndata) private pure {
        if (returndata.length > 0) {
            revert("Address: low-level call failed");
        } else {
            revert("Address: low-level call failed");
        }
    }
}