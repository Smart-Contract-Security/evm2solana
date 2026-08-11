import {Errors} from "./Errors.sol";
import {AccountInfo} from "solana";

library Address {
    error AddressEmptyCode(address target);

    function sendValue(address payable recipient, uint64 amount) internal {
        AccountInfo account = tx.accounts.recipient;
        if (account.lamports < amount) {
            revert Errors.InsufficientBalance(account.lamports, amount);
        }
        recipient.transfer(amount);
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        AccountInfo account = tx.accounts.target;
        if (account.lamports < value) {
            revert Errors.InsufficientBalance(account.lamports, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResult(success, returndata);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResult(success, returndata);
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