// SPDX-License-Identifier: MIT

import {IERC20} from "../IERC20.sol";

library SafeERC20 {
    function safeTransfer(address token, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        (bool success, bytes memory returndata) = token.call{accounts: []}(abi.encodeWithSelector(IERC20.allowance.selector, address(this), spender));
        uint64 oldAllowance = abi.decode(returndata, (uint64));
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint64 requestedDecrease) internal {
        unchecked {
            (bool success, bytes memory returndata) = token.call{accounts: []}(abi.encodeWithSelector(IERC20.allowance.selector, address(this), spender));
            uint64 currentAllowance = abi.decode(returndata, (uint64));
            if (currentAllowance < requestedDecrease) {
                revert();
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

    function transferAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!isContract(to)) {
            safeTransfer(token, to, value);
        } else {
            (bool success, bytes memory returndata) = token.call{accounts: []}(abi.encodeWithSelector(IERC1363.transferAndCall.selector, to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert();
            }
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint64 value,
        bytes memory data
    ) internal {
        if (!isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else {
            (bool success, bytes memory returndata) = token.call{accounts: []}(abi.encodeWithSelector(IERC1363.transferFromAndCall.selector, from, to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert();
            }
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!isContract(to)) {
            forceApprove(token, to, value);
        } else {
            (bool success, bytes memory returndata) = token.call{accounts: []}(abi.encodeWithSelector(IERC1363.approveAndCall.selector, to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert();
            }
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call{accounts: []}(data);
        if (!success) {
            revert();
        }
        if (returndata.length == 0) {
            if (!isContract(token)) {
                revert();
            }
        } else {
            bool returnValue = abi.decode(returndata, (bool));
            if (!returnValue) {
                revert();
            }
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call{accounts: []}(data);
        if (!success) {
            return false;
        }
        if (returndata.length == 0) {
            return isContract(token);
        } else {
            bool returnValue = abi.decode(returndata, (bool));
            return returnValue;
        }
    }

    function isContract(address account) private view returns (bool) {
        return account != address(0);
    }
}

interface IERC1363 {
    function transferAndCall(address to, uint64 value, bytes calldata data) external returns (bool);
    function transferFromAndCall(address from, address to, uint64 value, bytes calldata data) external returns (bool);
    function approveAndCall(address spender, uint64 value, bytes calldata data) external returns (bool);
}