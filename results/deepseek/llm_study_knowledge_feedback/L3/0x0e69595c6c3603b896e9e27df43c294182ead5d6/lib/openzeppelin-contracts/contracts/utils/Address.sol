import 'solana';

library Address {
    function sendValue(address payable recipient, uint64 amount) internal {
        if (tx.accounts.dataAccount.lamports < amount) {
            revert("Address: insufficient balance");
        }

        recipient.lamports += amount;
        tx.accounts.dataAccount.lamports -= amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        if (tx.accounts.dataAccount.lamports < value) {
            revert("Address: insufficient balance");
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
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
            if (returndata.length == 0 && target.code.length == 0) {
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