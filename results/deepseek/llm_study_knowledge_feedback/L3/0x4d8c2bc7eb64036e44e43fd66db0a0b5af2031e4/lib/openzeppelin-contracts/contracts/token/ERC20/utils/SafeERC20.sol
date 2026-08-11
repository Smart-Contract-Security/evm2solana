// SPDX-License-Identifier: MIT

library SafeERC20 {
    function safeTransfer(address token, address to, uint64 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert();
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
                revert();
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(address token, address spender, uint64 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert();
            if (!_safeApprove(token, spender, value, true)) revert();
        }
    }

    function transferAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            safeTransfer(token, to, value);
        } else if (!_transferAndCall(token, to, value, data)) {
            revert();
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
            revert();
        }
    }

    function approveAndCallRelaxed(address token, address to, uint64 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!_approveAndCall(token, to, value, data)) {
            revert();
        }
    }

    function _safeTransfer(address token, address to, uint64 value, bool bubble) private returns (bool success) {
        success = _transfer(token, to, value);
        if (!success) {
            if (bubble) {
                revert();
            }
            success = false;
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint64 value,
        bool bubble
    ) private returns (bool success) {
        success = _transferFrom(token, from, to, value);
        if (!success) {
            if (bubble) {
                revert();
            }
            success = false;
        }
    }

    function _safeApprove(address token, address spender, uint64 value, bool bubble) private returns (bool success) {
        success = _approve(token, spender, value);
        if (!success) {
            if (bubble) {
                revert();
            }
            success = false;
        }
    }

    function _isContract(address addr) private view returns (bool) {
        return addr != address(0);
    }

    // Low-level calls to token functions using external call with program_id
    // Since we don't have IERC20/IERC1363 interfaces, we use raw external calls
    // with the appropriate discriminators.

    function _transfer(address token, address to, uint64 value) private returns (bool) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("transfer(address,uint64)", to, value));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }

    function _transferFrom(address token, address from, address to, uint64 value) private returns (bool) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("transferFrom(address,address,uint64)", from, to, value));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }

    function _approve(address token, address spender, uint64 value) private returns (bool) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("approve(address,uint64)", spender, value));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }

    function _allowance(address token, address owner, address spender) private view returns (uint64) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("allowance(address,address)", owner, spender));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (uint64));
        }
        return 0;
    }

    function _transferAndCall(address token, address to, uint64 value, bytes memory data) private returns (bool) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("transferAndCall(address,uint64,bytes)", to, value, data));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }

    function _transferFromAndCall(address token, address from, address to, uint64 value, bytes memory data) private returns (bool) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("transferFromAndCall(address,address,uint64,bytes)", from, to, value, data));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }

    function _approveAndCall(address token, address to, uint64 value, bytes memory data) private returns (bool) {
        (bool success, bytes memory ret) = token.call{program_id: token}(abi.encodeWithSignature("approveAndCall(address,uint64,bytes)", to, value, data));
        if (success && ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }
}