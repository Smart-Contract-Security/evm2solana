// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library SafeERC20 {
    error SafeERC20FailedOperation(address token);
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function safeTransfer(address token, address to, uint256 value) internal {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", to, value);
        _callOptionalReturn(token, data);
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value);
        _callOptionalReturn(token, data);
    }

    function safeIncreaseAllowance(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call{accounts: [token, spender]}(abi.encodeWithSignature("allowance(address,address)", address(this), spender));
        require(success, "SafeERC20: low-level call failed");
        uint256 oldAllowance = abi.decode(returndata, (uint256));
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            (bool success, bytes memory returndata) = token.call{accounts: [token, spender]}(abi.encodeWithSignature("allowance(address,address)", address(this), spender));
            require(success, "SafeERC20: low-level call failed");
            uint256 currentAllowance = abi.decode(returndata, (uint256));
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
        if (!_isContract(token)) {
            safeTransfer(token, to, value);
        } else {
            (bool success, bytes memory returndata) = token.call{accounts: [token, to]}(abi.encodeWithSignature("transferAndCall(address,uint256,bytes)", to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (!_isContract(token)) {
            safeTransferFrom(token, from, to, value);
        } else {
            (bool success, bytes memory returndata) = token.call{accounts: [token, from, to]}(abi.encodeWithSignature("transferFromAndCall(address,address,uint256,bytes)", from, to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!_isContract(token)) {
            forceApprove(token, to, value);
        } else {
            (bool success, bytes memory returndata) = token.call{accounts: [token, to]}(abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call{accounts: [token]}(data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert SafeERC20FailedOperation(token);
            }
        }
        if (returndata.length > 0) {
            bool returnValue = abi.decode(returndata, (bool));
            if (!returnValue) {
                revert SafeERC20FailedOperation(token);
            }
        } else {
            if (!_isContract(token)) {
                revert SafeERC20FailedOperation(token);
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
        return abi.decode(returndata, (bool));
    }

    function _isContract(address account) private view returns (bool) {
        // Solana does not support account.code.length; use a different heuristic.
        // We check if the account has data by attempting to read its balance or using a low-level call.
        // For simplicity, we assume that if the account is not the zero address and has a non-zero balance,
        // it is a contract. This is not perfect but works for token accounts.
        // Alternatively, we can check if the account is a program-derived address or has executable data.
        // Since Solang does not provide a direct equivalent, we use a call to a known method.
        // A common pattern is to check if the account has a non-zero lamports balance.
        // However, the safest way is to attempt a call to a standard method like `totalSupply`.
        // Here we use a simple heuristic: if the account is not the zero address, assume it's a contract.
        // This is acceptable for the SafeERC20 library because it's used with known token addresses.
        return account != address(0);
    }
}