// SPDX-License-Identifier: MIT

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
}

interface IERC1363 is IERC20 {
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
                revert("SafeERC20: decrease allowance below zero");
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

    function _isContract(address account) private view returns (bool) {
        return account != address(0);
    }

    function _safeTransfer(address token, address to, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = IERC20.transfer.selector;
        bytes memory encoded = abi.encodeWithSelector(selector, to, value);
        (success, bytes memory returndata) = token.call{accounts: []}(encoded);
        if (success && returndata.length >= 32) {
            success = abi.decode(returndata, (bool));
        }
        if (!success) {
            if (bubble) {
                if (returndata.length > 0) {
                    revert(string(returndata));
                } else {
                    revert("SafeERC20: transfer failed");
                }
            } else {
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
        bytes memory encoded = abi.encodeWithSelector(selector, from, to, value);
        (success, bytes memory returndata) = token.call{accounts: []}(encoded);
        if (success && returndata.length >= 32) {
            success = abi.decode(returndata, (bool));
        }
        if (!success) {
            if (bubble) {
                if (returndata.length > 0) {
                    revert(string(returndata));
                } else {
                    revert("SafeERC20: transferFrom failed");
                }
            } else {
                success = false;
            }
        }
    }

    function _safeApprove(address token, address spender, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = IERC20.approve.selector;
        bytes memory encoded = abi.encodeWithSelector(selector, spender, value);
        (success, bytes memory returndata) = token.call{accounts: []}(encoded);
        if (success && returndata.length >= 32) {
            success = abi.decode(returndata, (bool));
        }
        if (!success) {
            if (bubble) {
                if (returndata.length > 0) {
                    revert(string(returndata));
                } else {
                    revert("SafeERC20: approve failed");
                }
            } else {
                success = false;
            }
        }
    }
}