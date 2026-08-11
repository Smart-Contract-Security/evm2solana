import 'solana';

library Address {
    function isContract(address account) internal view returns (bool) {
        AccountMeta[1] memory metas = [AccountMeta({pubkey: account, is_signer: false, is_writable: false})];
        (bool success, bytes memory returndata) = account.call{accounts: metas}(abi.encodeWithSignature("global:noop"));
        return success;
    }

    function sendValue(address payable recipient, uint64 amount) internal {
        AccountInfo memory recipientInfo = tx.accounts[recipient].accountInfo;
        require(recipientInfo.lamports >= amount, "Address: insufficient balance");

        recipient.transfer(amount);
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
        AccountInfo memory thisInfo = tx.accounts[address(this)].accountInfo;
        require(thisInfo.lamports >= value, "Address: insufficient balance for call");

        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: true})
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
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: false})
        ];

        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: true})
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
}