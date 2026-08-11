// SPDX-License-Identifier: MIT

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
        uint64 oldAllowance = _allowance(token, address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint64 requestedDecrease) internal {
        unchecked {
            uint64 currentAllowance = _allowance(token, address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert("SafeERC20: decrease exceeds allowance");
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
        } else if (!IERC1363(token).transferAndCall{accounts: [token, to]}(to, value, data)) {
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
        } else if (!IERC1363(token).transferFromAndCall{accounts: [token, from, to]}(from, to, value, data)) {
            revert("SafeERC20: transferFromAndCall failed");
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall{accounts: [token, to]}(to, value, data)) {
            revert("SafeERC20: approveAndCall failed");
        }
    }

    function _safeTransfer(address token, address to, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = _getSelector("transfer(address,uint64)");
        bytes memory encodedCall = abi.encodeWithSelector(selector, to, value);
        (success, bytes memory returndata) = token.call{accounts: [token, to]}(encodedCall);
        if (success && returndata.length > 0) {
            success = abi.decode(returndata, (bool));
        }
        if (!success) {
            if (bubble) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 32), mload(returndata))
                    }
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
        uint64 value,
        bool bubble
    ) private returns (bool success) {
        bytes8 selector = _getSelector("transferFrom(address,address,uint64)");
        bytes memory encodedCall = abi.encodeWithSelector(selector, from, to, value);
        (success, bytes memory returndata) = token.call{accounts: [token, from, to]}(encodedCall);
        if (success && returndata.length > 0) {
            success = abi.decode(returndata, (bool));
        }
        if (!success) {
            if (bubble) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 32), mload(returndata))
                    }
                } else {
                    revert("SafeERC20: transferFrom failed");
                }
            }
        }
    }

    function _safeApprove(address token, address spender, uint64 value, bool bubble) private returns (bool success) {
        bytes8 selector = _getSelector("approve(address,uint64)");
        bytes memory encodedCall = abi.encodeWithSelector(selector, spender, value);
        (success, bytes memory returndata) = token.call{accounts: [token, spender]}(encodedCall);
        if (success && returndata.length > 0) {
            success = abi.decode(returndata, (bool));
        }
        if (!success) {
            if (bubble) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 32), mload(returndata))
                    }
                } else {
                    revert("SafeERC20: approve failed");
                }
            }
        }
    }

    function _allowance(address token, address owner, address spender) private view returns (uint64) {
        bytes8 selector = _getSelector("allowance(address,address)");
        bytes memory encodedCall = abi.encodeWithSelector(selector, owner, spender);
        (bool success, bytes memory returndata) = token.call{accounts: [token, owner, spender]}(encodedCall);
        require(success, "SafeERC20: allowance query failed");
        return abi.decode(returndata, (uint64));
    }

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }

    function _getSelector(string memory signature) private pure returns (bytes8) {
        return bytes8(sha256(bytes(signature)));
    }
}