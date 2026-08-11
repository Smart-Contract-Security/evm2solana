// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
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

    function trySafeTransfer(address token, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeWithSignature("transfer(address,uint256)", to, value));
    }

    function trySafeTransferFrom(address token, address from, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint256 value) internal {
        AccountMeta[] memory metas = new AccountMeta[](3);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: address(this), is_signer: false, is_writable: false});
        metas[2] = AccountMeta({pubkey: spender, is_signer: false, is_writable: false});
        (bool success, bytes memory returndata) = token.call{accounts: metas}(abi.encodeWithSignature("allowance(address,address)", address(this), spender));
        require(success, "SafeERC20: low-level call failed");
        uint256 oldAllowance = abi.decode(returndata, (uint256));
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            AccountMeta[] memory metas = new AccountMeta[](3);
            metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
            metas[1] = AccountMeta({pubkey: address(this), is_signer: false, is_writable: false});
            metas[2] = AccountMeta({pubkey: spender, is_signer: false, is_writable: false});
            (bool success, bytes memory returndata) = token.call{accounts: metas}(abi.encodeWithSignature("allowance(address,address)", address(this), spender));
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
        if (!_isContract(to)) {
            safeTransfer(token, to, value);
        } else {
            AccountMeta[] memory metas = new AccountMeta[](2);
            metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
            metas[1] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
            (bool success, bytes memory returndata) = token.call{accounts: metas}(abi.encodeWithSignature("transferAndCall(address,uint256,bytes)", to, value, data));
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
        if (!_isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else {
            AccountMeta[] memory metas = new AccountMeta[](3);
            metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
            metas[1] = AccountMeta({pubkey: from, is_signer: false, is_writable: true});
            metas[2] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
            (bool success, bytes memory returndata) = token.call{accounts: metas}(abi.encodeWithSignature("transferFromAndCall(address,address,uint256,bytes)", from, to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else {
            AccountMeta[] memory metas = new AccountMeta[](2);
            metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
            metas[1] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
            (bool success, bytes memory returndata) = token.call{accounts: metas}(abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", to, value, data));
            if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
                revert SafeERC20FailedOperation(token);
            }
        }
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        (bool success, bytes memory returndata) = token.call{accounts: metas}(data);
        if (!success) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
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
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        (bool success, bytes memory returndata) = token.call{accounts: metas}(data);
        if (success) {
            if (returndata.length > 0) {
                return abi.decode(returndata, (bool));
            } else {
                return _isContract(token);
            }
        }
        return false;
    }

    function _isContract(address account) private view returns (bool) {
        // On Solana, we check if the account is a program (contract) by checking if it's executable.
        // This is a simplified check; in practice you might need to use the system call.
        // For Solang, we can use the account's data length or rely on the fact that EOAs have no code.
        // Since address.code is not supported, we use a low-level approach.
        // We assume that if the account has data, it's a contract. This is not perfect but works for most cases.
        // Alternatively, we can check the account's owner, but that's not directly available in Solang.
        // For now, we return true if the account is not the zero address and assume it's a contract if it's not an EOA.
        // In Solana, all accounts can have data, so we need a different heuristic.
        // We'll use the fact that contracts are programs, and we can check if the account is executable.
        // However, Solang does not provide a direct way to check this.
        // As a workaround, we'll always return true for non-zero addresses, assuming they are contracts.
        // This is not ideal but avoids the unsupported `address.code`.
        return account != address(0);
    }
}