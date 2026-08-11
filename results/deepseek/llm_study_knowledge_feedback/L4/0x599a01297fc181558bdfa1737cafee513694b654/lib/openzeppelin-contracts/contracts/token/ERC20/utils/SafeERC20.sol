import 'solana';

interface IERC20 {
    function transfer(address to, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
    function approve(address spender, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
}

interface IERC20Permit {
    function nonces(address owner) external view returns (uint64);
    function permit(
        address owner,
        address spender,
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

library SafeERC20 {
    function safeTransfer(address token, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
    }

    function safeApprove(address token, address spender, uint64 value) internal {
        require(
            (value == 0) || (IERC20(token).allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        uint64 oldAllowance = IERC20(token).allowance(address(this), spender);
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, oldAllowance + value));
    }

    function safeDecreaseAllowance(address token, address spender, uint64 value) internal {
        unchecked {
            uint64 oldAllowance = IERC20(token).allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, oldAllowance - value));
        }
    }

    function forceApprove(address token, address spender, uint64 value) internal {
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
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint64 nonceBefore = IERC20Permit(token).nonces(owner);
        IERC20Permit(token).permit(owner, spender, value, deadline, v, r, s);
        uint64 nonceAfter = IERC20Permit(token).nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = _functionCall(token, data, "SafeERC20: low-level call failed");
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory returndata) = token.call{accounts: metas}(data);
        return
            success && (returndata.length == 0 || abi.decode(returndata, (bool))) && _isContract(token);
    }

    function _functionCall(address target, bytes memory data, string memory errorMessage) private returns (bytes memory) {
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory returndata) = target.call{accounts: metas}(data);
        require(success, errorMessage);
        return returndata;
    }

    function _isContract(address account) private view returns (bool) {
        AccountInfo memory info = tx.accounts[account];
        return info.owner == account;
    }
}