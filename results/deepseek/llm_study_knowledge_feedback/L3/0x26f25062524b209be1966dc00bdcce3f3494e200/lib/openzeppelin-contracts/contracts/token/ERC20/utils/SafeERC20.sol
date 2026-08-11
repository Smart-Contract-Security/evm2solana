// SPDX-License-Identifier: MIT

import {IERC20} from "../IERC20.sol";
import {IERC1363} from "../../../interfaces/IERC1363.sol";

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
        if (!isContract(to)) {
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
        if (!isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else if (!IERC1363(token).transferFromAndCall(from, to, value, data)) {
            revert("SafeERC20: transferFromAndCall failed");
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!isContract(to)) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall(to, value, data)) {
            revert("SafeERC20: approveAndCall failed");
        }
    }

    function isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }

    function _safeTransfer(address token, address to, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = IERC20.transfer.selector;
        (bool callSuccess, bytes memory returnData) = token.call{value: 0}(abi.encodeWithSelector(selector, to, value));
        success = callSuccess;
        if (callSuccess) {
            if (returnData.length > 0) {
                success = abi.decode(returnData, (bool));
            }
        }
        if (!success) {
            if (!callSuccess && bubble) {
                if (returnData.length > 0) {
                    assembly {
                        revert(add(returnData, 0x20), mload(returnData))
                    }
                } else {
                    revert("SafeERC20: transfer failed");
                }
            }
            if (callSuccess && returnData.length == 0) {
                success = true;
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
        (bool callSuccess, bytes memory returnData) = token.call{value: 0}(abi.encodeWithSelector(selector, from, to, value));
        success = callSuccess;
        if (callSuccess) {
            if (returnData.length > 0) {
                success = abi.decode(returnData, (bool));
            }
        }
        if (!success) {
            if (!callSuccess && bubble) {
                if (returnData.length > 0) {
                    assembly {
                        revert(add(returnData, 0x20), mload(returnData))
                    }
                } else {
                    revert("SafeERC20: transferFrom failed");
                }
            }
            if (callSuccess && returnData.length == 0) {
                success = true;
            }
        }
    }

    function _safeApprove(address token, address spender, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = IERC20.approve.selector;
        (bool callSuccess, bytes memory returnData) = token.call{value: 0}(abi.encodeWithSelector(selector, spender, value));
        success = callSuccess;
        if (callSuccess) {
            if (returnData.length > 0) {
                success = abi.decode(returnData, (bool));
            }
        }
        if (!success) {
            if (!callSuccess && bubble) {
                if (returnData.length > 0) {
                    assembly {
                        revert(add(returnData, 0x20), mload(returnData))
                    }
                } else {
                    revert("SafeERC20: approve failed");
                }
            }
            if (callSuccess && returnData.length == 0) {
                success = true;
            }
        }
    }
}