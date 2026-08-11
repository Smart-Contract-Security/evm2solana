import {Errors} from "./Errors.sol";

library Address {
    function sendValue(address payable recipient, uint64 amount) internal {
        if (recipient.lamports < amount) {
            revert("InsufficientBalance");
        }
        recipient.lamports += amount;
        tx.accounts.dataAccount.lamports -= amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        if (tx.accounts.dataAccount.lamports < value) {
            revert("InsufficientBalance");
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }
}