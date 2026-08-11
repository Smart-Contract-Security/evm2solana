import {IERC1363} from "../../../interfaces/IERC1363.sol";

library SafeERC20 {
    error SafeERC20FailedOperation(address token);
    error SafeERC20FailedDecreaseAllowance(address spender, uint64 currentAllowance, uint64 requestedDecrease);

    function safeTransfer(address token, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint64)", to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("transferFrom(address,address,uint64)", from, to, value));
    }

    function trySafeTransfer(address token, address to, uint64 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeWithSignature("transfer(address,uint64)", to, value));
    }

    function trySafeTransferFrom(address token, address from, address to, uint64 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeWithSignature("transferFrom(address,address,uint64)", from, to, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        (bool success, bytes memory returnData) = token.call{accounts: []}(abi.encodeWithSignature("allowance(address,address)", address(this), spender));
        require(success, "SafeERC20: allowance call failed");
        uint64 oldAllowance = abi.decode(returnData, (uint64));
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint64 requestedDecrease) internal {
        unchecked {
            (bool success, bytes memory returnData) = token.call{accounts: []}(abi.encodeWithSignature("allowance(address,address)", address(this), spender));
            require(success, "SafeERC20: allowance call failed");
            uint64 currentAllowance = abi.decode(returnData, (uint64));
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint64 value) internal {
        bytes memory approvalCall = abi.encodeWithSignature("approve(address,uint64)", spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSignature("approve(address,uint64)", spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    function transferAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            safeTransfer(token, to, value);
        } else if (!IERC1363(token).transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint64 value,
        bytes memory data
    ) internal {
        if (!_isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else if (!IERC1363(token).transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returnData) = token.call{accounts: []}(data);
        if (!success) {
            revert SafeERC20FailedOperation(token);
        }
        if (returnData.length == 0) {
            if (!_isContract(token)) {
                revert SafeERC20FailedOperation(token);
            }
        } else {
            bool returnValue = abi.decode(returnData, (bool));
            if (!returnValue) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returnData) = token.call{accounts: []}(data);
        if (!success) {
            return false;
        }
        if (returnData.length == 0) {
            return _isContract(token);
        } else {
            bool returnValue = abi.decode(returnData, (bool));
            return returnValue;
        }
    }

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }
}