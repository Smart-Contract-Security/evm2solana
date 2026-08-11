import 'solana';

library Address {
    function isContract(address account) internal view returns (bool) {
        AccountInfo memory info = tx.accounts[uint256(account)];
        return info.executable;
    }

    function sendValue(address payable recipient, uint64 amount) internal {
        AccountInfo memory thisInfo = tx.accounts[uint256(address(this))];
        require(thisInfo.lamports >= amount, "Address: insufficient balance");

        AccountInfo memory recipientInfo = tx.accounts[uint256(recipient)];
        recipientInfo.lamports += amount;
        thisInfo.lamports -= amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value, string memory errorMessage) internal returns (bytes memory) {
        AccountInfo memory thisInfo = tx.accounts[uint256(address(this))];
        require(thisInfo.lamports >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        AccountInfo memory targetInfo = tx.accounts[uint256(target)];
        targetInfo.lamports += value;
        thisInfo.lamports -= value;

        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: true}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");
        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: false})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: true}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                revert(errorMessage);
            } else {
                revert(errorMessage);
            }
        }
    }
}