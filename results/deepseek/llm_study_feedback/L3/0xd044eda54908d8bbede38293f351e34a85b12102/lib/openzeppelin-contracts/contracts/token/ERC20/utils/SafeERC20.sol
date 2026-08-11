// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
import {IERC20Permit} from "../extensions/IERC20Permit.sol";

library SafeERC20 {
    // Custom errors are not supported on Solana; use string reverts instead.
    // error SafeERC20FailedOperation(address token);
    // error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function safeTransfer(address token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint256 value) internal {
        // IERC20 is an interface; we cast token to IERC20 to call allowance.
        uint256 oldAllowance = IERC20(token).allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                // revert with custom errors not supported on Solana; use string revert.
                revert("SafeERC20: decreased allowance below zero");
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
        bytes memory returndata = _functionCall(token, data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            // revert with custom errors not supported on Solana; use string revert.
            revert("SafeERC20: ERC20 operation did not succeed");
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        // 'accounts' takes array of AccountMeta, not 'address[1]'.
        // Use the correct Solana syntax: create an array of AccountMeta with one element.
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        (bool success, bytes memory returndata) = token.call{accounts: metas}(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && token.code.length > 0;
    }

    function _functionCall(address target, bytes memory data) private returns (bytes memory) {
        // 'accounts' takes array of AccountMeta, not 'address[1]'.
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: true});
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
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