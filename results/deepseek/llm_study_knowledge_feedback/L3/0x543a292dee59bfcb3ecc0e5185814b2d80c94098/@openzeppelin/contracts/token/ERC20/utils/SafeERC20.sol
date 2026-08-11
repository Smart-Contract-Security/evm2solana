// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

library SafeERC20 {
    function safeTransfer(address token, address to, uint64 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert("SafeERC20: transfer failed");
        }
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert("SafeERC20: transferFrom failed");
        }
    }

    function trySafeTransfer(address token, address to, uint64 value) internal returns (bool) {
        return _safeTransfer(token, to, value, false);
    }

    function trySafeTransferFrom(address token, address from, address to, uint64 value) internal returns (bool) {
        return _safeTransferFrom(token, from, to, value, false);
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        uint64 oldAllowance = _allowance(token, address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint64 requestedDecrease) internal {
        unchecked {
            uint64 currentAllowance = _allowance(token, address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert("SafeERC20: decreased allowance below zero");
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint64 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert("SafeERC20: approve failed");
            if (!_safeApprove(token, spender, value, true)) revert("SafeERC20: approve failed");
        }
    }

    function transferAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            safeTransfer(token, to, value);
        } else if (!_transferAndCall(token, to, value, data)) {
            revert("SafeERC20: transferAndCall failed");
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
        } else if (!_transferFromAndCall(token, from, to, value, data)) {
            revert("SafeERC20: transferFromAndCall failed");
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!_approveAndCall(token, to, value, data)) {
            revert("SafeERC20: approveAndCall failed");
        }
    }

    function _safeTransfer(address token, address to, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = 0xa9059cbb00000000;

        AccountMeta[3] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false})
        ];

        bytes data = abi.encodeWithSelector(selector, to, value);
        (success, bytes memory returndata) = token.call{accounts: metas}(data);
        if (!success) {
            if (bubble) {
                revert("SafeERC20: transfer failed");
            }
            success = false;
        } else {
            success = abi.decode(returndata, (bool));
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint64 value,
        bool bubble
    ) private returns (bool success) {
        bytes8 selector = 0x23b872dd00000000;

        AccountMeta[4] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: from, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false})
        ];

        bytes data = abi.encodeWithSelector(selector, from, to, value);
        (success, bytes memory returndata) = token.call{accounts: metas}(data);
        if (!success) {
            if (bubble) {
                revert("SafeERC20: transferFrom failed");
            }
            success = false;
        } else {
            success = abi.decode(returndata, (bool));
        }
    }

    function _safeApprove(address token, address spender, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = 0x095ea7b300000000;

        AccountMeta[3] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: spender, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false})
        ];

        bytes data = abi.encodeWithSelector(selector, spender, value);
        (success, bytes memory returndata) = token.call{accounts: metas}(data);
        if (!success) {
            if (bubble) {
                revert("SafeERC20: approve failed");
            }
            success = false;
        } else {
            success = abi.decode(returndata, (bool));
        }
    }

    function _allowance(address token, address owner, address spender) private returns (uint64) {
        bytes8 selector = 0xdd62ed3e00000000;

        AccountMeta[3] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: false}),
            AccountMeta({pubkey: owner, is_signer: false, is_writable: false}),
            AccountMeta({pubkey: spender, is_signer: false, is_writable: false})
        ];

        bytes data = abi.encodeWithSelector(selector, owner, spender);
        (bool success, bytes memory returndata) = token.call{accounts: metas}(data);
        if (success) {
            return abi.decode(returndata, (uint64));
        }
        return 0;
    }

    function _transferAndCall(address token, address to, uint64 value, bytes memory data) private returns (bool) {
        bytes8 selector = 0x4000aea000000000;

        AccountMeta[3] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false})
        ];

        bytes memory callData = abi.encodeWithSelector(selector, to, value, data);
        (bool success, bytes memory returndata) = token.call{accounts: metas}(callData);
        if (success) {
            return abi.decode(returndata, (bool));
        }
        return false;
    }

    function _transferFromAndCall(address token, address from, address to, uint64 value, bytes memory data) private returns (bool) {
        bytes8 selector = 0xc1d34b8900000000;

        AccountMeta[4] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: from, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false})
        ];

        bytes memory callData = abi.encodeWithSelector(selector, from, to, value, data);
        (bool success, bytes memory returndata) = token.call{accounts: metas}(callData);
        if (success) {
            return abi.decode(returndata, (bool));
        }
        return false;
    }

    function _approveAndCall(address token, address spender, uint64 value, bytes memory data) private returns (bool) {
        bytes8 selector = 0xcae9ca5100000000;

        AccountMeta[3] metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: spender, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(this), is_signer: false, is_writable: false})
        ];

        bytes memory callData = abi.encodeWithSelector(selector, spender, value, data);
        (bool success, bytes memory returndata) = token.call{accounts: metas}(callData);
        if (success) {
            return abi.decode(returndata, (bool));
        }
        return false;
    }

    function _isContract(address account) private view returns (bool) {
        return account != address(0);
    }
}