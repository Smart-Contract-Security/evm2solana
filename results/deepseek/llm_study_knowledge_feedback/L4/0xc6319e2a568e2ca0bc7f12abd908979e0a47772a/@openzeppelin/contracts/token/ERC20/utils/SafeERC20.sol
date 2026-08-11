// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

import {IERC20} from "../IERC20.sol";
import {IERC20Permit} from "../extensions/IERC20Permit.sol";
import {AccountInfo} from "solana";

library SafeERC20 {
    function safeTransfer(address token, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        uint64 oldAllowance = IERC20(token).allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint64 requestedDecrease) internal {
        unchecked {
            uint64 currentAllowance = IERC20(token).allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert("SafeERC20: decreased allowance below zero");
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint64 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(IERC20.approve.selector, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = _functionCall(token, data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert("SafeERC20: ERC20 operation did not succeed");
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = _call(token, data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && _codeSize(token) > 0;
    }

    function _functionCall(address target, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returndata) = _call(target, data);
        if (!success) {
            revert("SafeERC20: low-level call failed");
        }
        return returndata;
    }

    function _call(address target, bytes memory data) private returns (bool, bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        return (success, returndata);
    }

    function _codeSize(address target) private view returns (uint64) {
        AccountInfo account = tx.accounts[target];
        return uint64(account.data.length);
    }
}