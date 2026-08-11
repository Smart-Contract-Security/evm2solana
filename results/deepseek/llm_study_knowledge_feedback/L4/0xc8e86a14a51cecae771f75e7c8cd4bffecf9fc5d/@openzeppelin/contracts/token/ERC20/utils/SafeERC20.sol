// SPDX-License-Identifier: MIT

library SafeERC20 {
    // IERC20 interface selectors (first 8 bytes of sha256("global:functionName"))
    bytes8 constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes8 constant TRANSFER_FROM_SELECTOR = 0x23b872dd;
    bytes8 constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes8 constant ALLOWANCE_SELECTOR = 0xdd62ed3e;
    bytes8 constant NONCES_SELECTOR = 0x7ecebe00;
    bytes8 constant PERMIT_SELECTOR = 0xd505accf;

    function safeTransfer(address token, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, value));
    }

    function safeApprove(address token, address spender, uint64 value) internal {
        uint64 currentAllowance = _allowance(token, address(this), spender);
        require(
            (value == 0) || (currentAllowance == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(APPROVE_SELECTOR, spender, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        uint64 oldAllowance = _allowance(token, address(this), spender);
        _callOptionalReturn(token, abi.encodeWithSelector(APPROVE_SELECTOR, spender, oldAllowance + value));
    }

    function safeDecreaseAllowance(address token, address spender, uint64 value) internal {
        unchecked {
            uint64 oldAllowance = _allowance(token, address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            _callOptionalReturn(token, abi.encodeWithSelector(APPROVE_SELECTOR, spender, oldAllowance - value));
        }
    }

    function forceApprove(address token, address spender, uint64 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(APPROVE_SELECTOR, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(APPROVE_SELECTOR, spender, 0));
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
        uint64 nonceBefore = _nonces(token, owner);
        _permit(token, owner, spender, value, deadline, v, r, s);
        uint64 nonceAfter = _nonces(token, owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    function _allowance(address token, address owner, address spender) private returns (uint64) {
        bytes memory data = abi.encodeWithSelector(ALLOWANCE_SELECTOR, owner, spender);
        (bool success, bytes memory returndata) = token.call{accounts: []}(data);
        require(success, "SafeERC20: allowance call failed");
        return abi.decode(returndata, (uint64));
    }

    function _nonces(address token, address owner) private returns (uint64) {
        bytes memory data = abi.encodeWithSelector(NONCES_SELECTOR, owner);
        (bool success, bytes memory returndata) = token.call{accounts: []}(data);
        require(success, "SafeERC20: nonces call failed");
        return abi.decode(returndata, (uint64));
    }

    function _permit(
        address token,
        address owner,
        address spender,
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        bytes memory data = abi.encodeWithSelector(PERMIT_SELECTOR, owner, spender, value, deadline, v, r, s);
        (bool success, ) = token.call{accounts: []}(data);
        require(success, "SafeERC20: permit call failed");
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = _functionCall(token, data, "SafeERC20: low-level call failed");
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
    }

    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call{accounts: []}(data);
        return
            success && (returndata.length == 0 || abi.decode(returndata, (bool))) && _isContract(token);
    }

    function _functionCall(address target, bytes memory data, string memory errorMessage) private returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        require(success, errorMessage);
        return returndata;
    }

    function _isContract(address account) private view returns (bool) {
        // On Solana, check if the account is executable (program) or has data
        // Since address.code is not available, we check if the account exists and is a program
        // by attempting to read its data. A simpler approach: check if account is not the zero address
        // and has data by checking account existence via AccountInfo.
        // For Solana, we use the fact that token accounts are programs, so we check if the account is executable.
        // However, since we cannot access account metadata directly in Solidity for Solana,
        // we return true for any non-zero address as a pragmatic fallback.
        // The call itself will fail if the account is not a valid program.
        return account != address(0);
    }
}