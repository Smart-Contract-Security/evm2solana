// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Solang on Solana does not support importing external interfaces in the same way.
// We define minimal interfaces inline to satisfy the compiler.
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IERC20Permit {
    function nonces(address owner) external view returns (uint256);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

library SafeERC20 {
    function safeTransfer(address token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
    }

    function safeApprove(address token, address spender, uint256 value) internal {
        require(
            (value == 0) || (IERC20(token).allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint256 value) internal {
        uint256 oldAllowance = IERC20(token).allowance(address(this), spender);
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, oldAllowance + value));
    }

    function safeDecreaseAllowance(address token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = IERC20(token).allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, oldAllowance - value));
        }
    }

    function forceApprove(address token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(IERC20.approve.selector, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    function safePermit(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = IERC20Permit(token).nonces(owner);
        IERC20Permit(token).permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = IERC20Permit(token).nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = functionCall(token, data, "SafeERC20: low-level call failed");
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call{accounts: getAccountMeta(token)}(data);
        return
            success && (returndata.length == 0 || abi.decode(returndata, (bool))) && isContract(token);
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) private returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: getAccountMeta(target)}(data);
        require(success, errorMessage);
        return returndata;
    }

    // Solana does not have `address.code`. We use a different approach to check if an account is a contract.
    // On Solana, all accounts are "contracts" (programs or data accounts). We check if the account is executable.
    function isContract(address account) private view returns (bool) {
        // In Solang for Solana, we can check if an account is a program by using `account.is_program()` or similar.
        // However, the simplest portable way is to check if the account has data or is executable.
        // Since `address.code` is not available, we use `account.code_length` which is supported by Solang.
        return account.code_length > 0;
    }

    // Helper to create AccountMeta array for cross-contract calls.
    // Solang requires an array of AccountMeta, not a plain address array.
    function getAccountMeta(address target) private pure returns (AccountMeta[] memory) {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: true});
        return metas;
    }
}