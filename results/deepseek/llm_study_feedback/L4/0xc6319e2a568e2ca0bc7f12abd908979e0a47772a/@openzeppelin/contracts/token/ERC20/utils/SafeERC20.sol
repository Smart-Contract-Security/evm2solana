// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
import {IERC20Permit} from "../extensions/IERC20Permit.sol";

library SafeERC20 {
    error SafeERC20FailedOperation(address token);
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function safeTransfer(address token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint256 value) internal {
        uint256 oldAllowance = IERC20(token).allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSignature("approve(address,uint256)", spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSignature("approve(address,uint256)", spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = functionCall(token, data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call{accounts: [token]} (data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && token.code.length > 0;
    }

    function functionCall(address target, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: [target]} (data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert("SafeERC20: low-level call failed");
            }
        }
        return returndata;
    }
}