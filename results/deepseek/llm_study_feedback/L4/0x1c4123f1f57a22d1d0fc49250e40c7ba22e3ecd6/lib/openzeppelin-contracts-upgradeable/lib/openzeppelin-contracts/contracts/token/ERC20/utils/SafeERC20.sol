// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Inline minimal interfaces to avoid import issues
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IERC1363 {
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

library SafeERC20 {
    function safeTransfer(address token, address to, uint256 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert("SafeERC20: transfer failed");
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert("SafeERC20: transferFrom failed");
        }
    }

    function trySafeTransfer(address token, address to, uint256 value) internal returns (bool) {
        return _safeTransfer(token, to, value, false);
    }

    function trySafeTransferFrom(address token, address from, address to, uint256 value) internal returns (bool) {
        return _safeTransferFrom(token, from, to, value, false);
    }

    function safeIncreaseAllowance(address token, address spender, uint256 value) internal {
        uint256 oldAllowance = IERC20(token).allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert("SafeERC20: decrease allowance below zero");
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint256 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert("SafeERC20: approve failed");
            if (!_safeApprove(token, spender, value, true)) revert("SafeERC20: approve failed");
        }
    }

    function transferAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!IERC1363(token).transferAndCall(to, value, data)) {
            revert("SafeERC20: transferAndCall failed");
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (!IERC1363(token).transferFromAndCall(from, to, value, data)) {
            revert("SafeERC20: transferFromAndCall failed");
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!IERC1363(token).approveAndCall(to, value, data)) {
            revert("SafeERC20: approveAndCall failed");
        }
    }

    function _safeTransfer(address token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));
        bytes memory encodedCall = abi.encodeWithSelector(selector, to, value);
        (success, bytes memory returndata) = token.call{gas: gasleft()}(encodedCall);
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
            }
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = bytes4(keccak256("transferFrom(address,address,uint256)"));
        bytes memory encodedCall = abi.encodeWithSelector(selector, from, to, value);
        (success, bytes memory returndata) = token.call{gas: gasleft()}(encodedCall);
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
            }
        }
    }

    function _safeApprove(address token, address spender, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = bytes4(keccak256("approve(address,uint256)"));
        bytes memory encodedCall = abi.encodeWithSelector(selector, spender, value);
        (success, bytes memory returndata) = token.call{gas: gasleft()}(encodedCall);
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
            }
        }
    }
}