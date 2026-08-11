// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
import {IERC1363} from "../../../interfaces/IERC1363.sol";

library SafeERC20 {
    error SafeERC20FailedOperation(address token);
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function safeTransfer(address token, address to, uint256 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert SafeERC20FailedOperation(token);
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
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint256 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert SafeERC20FailedOperation(token);
            if (!_safeApprove(token, spender, value, true)) revert SafeERC20FailedOperation(token);
        }
    }

    function transferAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!IERC1363(token).transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function transferFromAndCallRelaxed(
        address token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!IERC1363(token).transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function _safeTransfer(address token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes memory encodedCall = abi.encodeWithSelector(IERC20.transfer.selector, to, value);
        (success, bytes memory returndata) = token.call{accounts: [token, to]}(encodedCall);
        if (success) {
            if (returndata.length == 0) {
                success = true;
            } else {
                success = abi.decode(returndata, (bool));
            }
        } else {
            if (bubble) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
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
        bytes memory encodedCall = abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value);
        (success, bytes memory returndata) = token.call{accounts: [token, from, to]}(encodedCall);
        if (success) {
            if (returndata.length == 0) {
                success = true;
            } else {
                success = abi.decode(returndata, (bool));
            }
        } else {
            if (bubble) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
            success = false;
        }
    }

    function _safeApprove(address token, address spender, uint256 value, bool bubble) private returns (bool success) {
        bytes memory encodedCall = abi.encodeWithSelector(IERC20.approve.selector, spender, value);
        (success, bytes memory returndata) = token.call{accounts: [token, spender]}(encodedCall);
        if (success) {
            if (returndata.length == 0) {
                success = true;
            } else {
                success = abi.decode(returndata, (bool));
            }
        } else {
            if (bubble) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
            success = false;
        }
    }
}