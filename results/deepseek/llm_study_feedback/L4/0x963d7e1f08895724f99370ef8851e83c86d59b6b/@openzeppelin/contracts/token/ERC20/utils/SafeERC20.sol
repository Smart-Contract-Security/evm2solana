// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// IERC20 interface definition inline to avoid import issues
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
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
        (bool success, ) = token.call(abi.encodeWithSignature("transferAndCall(address,uint256,bytes)", to, value, data));
        if (!success) {
            safeTransfer(token, to, value);
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, ) = token.call(abi.encodeWithSignature("transferFromAndCall(address,address,uint256,bytes)", from, to, value, data));
        if (!success) {
            safeTransferFrom(token, from, to, value);
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        (bool success, ) = token.call(abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", to, value, data));
        if (!success) {
            forceApprove(token, to, value);
        }
    }

    function _safeTransfer(address token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));
        (bool ret, bytes memory returndata) = token.call{gas: gasleft()}(abi.encodeWithSelector(selector, to, value));
        success = ret;
        if (!ret || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            if (!ret && bubble) {
                if (returndata.length > 0) {
                    revert("SafeERC20: low-level call failed");
                } else {
                    revert("SafeERC20: low-level call failed");
                }
            }
            success = false;
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
        (bool ret, bytes memory returndata) = token.call{gas: gasleft()}(abi.encodeWithSelector(selector, from, to, value));
        success = ret;
        if (!ret || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            if (!ret && bubble) {
                if (returndata.length > 0) {
                    revert("SafeERC20: low-level call failed");
                } else {
                    revert("SafeERC20: low-level call failed");
                }
            }
            success = false;
        }
    }

    function _safeApprove(address token, address spender, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = bytes4(keccak256("approve(address,uint256)"));
        (bool ret, bytes memory returndata) = token.call{gas: gasleft()}(abi.encodeWithSelector(selector, spender, value));
        success = ret;
        if (!ret || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            if (!ret && bubble) {
                if (returndata.length > 0) {
                    revert("SafeERC20: low-level call failed");
                } else {
                    revert("SafeERC20: low-level call failed");
                }
            }
            success = false;
        }
    }
}