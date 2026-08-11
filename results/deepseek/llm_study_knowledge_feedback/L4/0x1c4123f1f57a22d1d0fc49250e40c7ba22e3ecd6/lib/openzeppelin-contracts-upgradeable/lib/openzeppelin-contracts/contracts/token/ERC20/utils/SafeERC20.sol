// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (token/ERC20/utils/SafeERC20.sol)

import {IERC20} from "../IERC20.sol";

interface IERC1363 {
    function transferAndCall(address to, uint64 value, bytes calldata data) external returns (bool);
    function transferFromAndCall(address from, address to, uint64 value, bytes calldata data) external returns (bool);
    function approveAndCall(address spender, uint64 value, bytes calldata data) external returns (bool);
}

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
        uint64 oldAllowance = IERC20(token).allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint64 requestedDecrease) internal {
        unchecked {
            uint64 currentAllowance = IERC20(token).allowance(address(this), spender);
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
        } else if (!IERC1363(token).transferAndCall(to, value, data)) {
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
        } else if (!IERC1363(token).transferFromAndCall(from, to, value, data)) {
            revert("SafeERC20: transferFromAndCall failed");
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall(to, value, data)) {
            revert("SafeERC20: approveAndCall failed");
        }
    }

    function _safeTransfer(address token, address to, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = IERC20.transfer.selector;
        bytes memory encodedCall = abi.encodeWithSelector(selector, to, value);
        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true})
        ];
        (success, bytes memory returndata) = token.call{accounts: metas}(encodedCall);
        if (success && returndata.length >= 32) {
            bool returnValue = abi.decode(returndata, (bool));
            if (!returnValue) {
                if (bubble) {
                    revert("SafeERC20: transfer failed");
                }
                success = false;
            }
        } else {
            if (!success && bubble) {
                revert("SafeERC20: transfer failed");
            }
            if (success && returndata.length == 0) {
                success = true;
            } else if (!success) {
                success = false;
            }
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint64 value,
        bool bubble
    ) private returns (bool success) {
        bytes8 selector = IERC20.transferFrom.selector;
        bytes memory encodedCall = abi.encodeWithSelector(selector, from, to, value);
        AccountMeta[3] memory metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: from, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true})
        ];
        (success, bytes memory returndata) = token.call{accounts: metas}(encodedCall);
        if (success && returndata.length >= 32) {
            bool returnValue = abi.decode(returndata, (bool));
            if (!returnValue) {
                if (bubble) {
                    revert("SafeERC20: transferFrom failed");
                }
                success = false;
            }
        } else {
            if (!success && bubble) {
                revert("SafeERC20: transferFrom failed");
            }
            if (success && returndata.length == 0) {
                success = true;
            } else if (!success) {
                success = false;
            }
        }
    }

    function _safeApprove(address token, address spender, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = IERC20.approve.selector;
        bytes memory encodedCall = abi.encodeWithSelector(selector, spender, value);
        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: spender, is_signer: false, is_writable: true})
        ];
        (success, bytes memory returndata) = token.call{accounts: metas}(encodedCall);
        if (success && returndata.length >= 32) {
            bool returnValue = abi.decode(returndata, (bool));
            if (!returnValue) {
                if (bubble) {
                    revert("SafeERC20: approve failed");
                }
                success = false;
            }
        } else {
            if (!success && bubble) {
                revert("SafeERC20: approve failed");
            }
            if (success && returndata.length == 0) {
                success = true;
            } else if (!success) {
                success = false;
            }
        }
    }

    function _isContract(address account) private view returns (bool) {
        return account != address(0);
    }
}