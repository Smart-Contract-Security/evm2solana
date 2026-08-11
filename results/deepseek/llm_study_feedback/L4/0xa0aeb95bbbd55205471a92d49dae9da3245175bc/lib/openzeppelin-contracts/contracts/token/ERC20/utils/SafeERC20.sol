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
        uint256 oldAllowance = _allowance(token, address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = _allowance(token, address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSignature("approve(address,uint256)", spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            bytes memory resetCall = abi.encodeWithSignature("approve(address,uint256)", spender, 0);
            _callOptionalReturn(token, resetCall);
            _callOptionalReturn(token, approvalCall);
        }
    }

    function transferAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!isContract(to)) {
            safeTransfer(token, to, value);
        } else {
            bytes memory callData = abi.encodeWithSignature("transferAndCall(address,uint256,bytes)", to, value, data);
            (bool success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token)}(callData);
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
        if (!isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else {
            bytes memory callData = abi.encodeWithSignature("transferFromAndCall(address,address,uint256,bytes)", from, to, value, data);
            (bool success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token)}(callData);
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!isContract(to)) {
            forceApprove(token, to, value);
        } else {
            bytes memory callData = abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", to, value, data);
            (bool success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token)}(callData);
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token)}(data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert SafeERC20FailedOperation(token);
            }
        } else {
            if (returndata.length > 0) {
                bool returnValue = abi.decode(returndata, (bool));
                if (!returnValue) {
                    revert SafeERC20FailedOperation(token);
                }
            } else {
                if (!isContract(token)) {
                    revert SafeERC20FailedOperation(token);
                }
            }
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token)}(data);
        if (success) {
            if (returndata.length == 0) {
                return isContract(token);
            } else {
                return abi.decode(returndata, (bool));
            }
        } else {
            return false;
        }
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _allowance(address token, address owner, address spender) private view returns (uint256) {
        bytes memory data = abi.encodeWithSignature("allowance(address,address)", owner, spender);
        (bool success, bytes memory returndata) = token.staticcall{accounts: _buildAccountMeta(token)}(data);
        require(success, "SafeERC20: allowance query failed");
        return abi.decode(returndata, (uint256));
    }

    function _buildAccountMeta(address token) private pure returns (AccountMeta[] memory) {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        return metas;
    }
}