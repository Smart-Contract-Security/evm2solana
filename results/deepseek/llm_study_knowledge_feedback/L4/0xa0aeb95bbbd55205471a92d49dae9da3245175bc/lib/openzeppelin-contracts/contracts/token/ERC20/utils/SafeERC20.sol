// SPDX-License-Identifier: MIT

import {IERC1363} from "../../../interfaces/IERC1363.sol";

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
        (bool success, bytes memory returndata) = token.call{accounts: [token, spender]}(
            abi.encodeWithSignature("allowance(address,address)", address(this), spender)
        );
        uint256 oldAllowance = 0;
        if (success && returndata.length >= 32) {
            oldAllowance = abi.decode(returndata, (uint256));
        }
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            (bool success, bytes memory returndata) = token.call{accounts: [token, spender]}(
                abi.encodeWithSignature("allowance(address,address)", address(this), spender)
            );
            uint256 currentAllowance = 0;
            if (success && returndata.length >= 32) {
                currentAllowance = abi.decode(returndata, (uint256));
            }
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

    function transferAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!_isContract(to)) {
            safeTransfer(token, to, value);
        } else if (!IERC1363(token).transferAndCall{accounts: [token, to]}(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (!_isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else if (!IERC1363(token).transferFromAndCall{accounts: [token, from, to]}(from, to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall{accounts: [token, to]}(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call{accounts: [token]}(data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(returndata, 32), returndata_size)
                }
            } else {
                revert SafeERC20FailedOperation(token);
            }
        } else {
            if (returndata.length == 0) {
                if (!_isContract(token)) {
                    revert SafeERC20FailedOperation(token);
                }
            } else {
                uint256 returnValue = abi.decode(returndata, (uint256));
                if (returnValue != 1) {
                    revert SafeERC20FailedOperation(token);
                }
            }
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call{accounts: [token]}(data);
        if (!success) {
            return false;
        }
        if (returndata.length == 0) {
            return _isContract(token);
        }
        uint256 returnValue = abi.decode(returndata, (uint256));
        return returnValue == 1;
    }

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }
}