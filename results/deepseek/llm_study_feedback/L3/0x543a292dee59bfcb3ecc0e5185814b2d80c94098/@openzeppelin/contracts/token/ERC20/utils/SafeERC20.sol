// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
        uint256 oldAllowance = _allowance(token, address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(address token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = _allowance(token, address(this), spender);
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
        if (!_isContract(to)) {
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
        if (!_isContract(to)) {
            safeTransferFrom(token, from, to, value);
        } else if (!IERC1363(token).transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function approveAndCallRelaxed(address token, address to, uint256 value, bytes memory data) internal {
        if (!_isContract(to)) {
            forceApprove(token, to, value);
        } else if (!IERC1363(token).approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(token);
        }
    }

    function _safeTransfer(address token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes memory encodedCall = abi.encodeWithSelector(0xa9059cbb, to, value);
        (success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token, to)}(encodedCall);
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
        bytes memory encodedCall = abi.encodeWithSelector(0x23b872dd, from, to, value);
        (success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token, from, to)}(encodedCall);
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
        bytes memory encodedCall = abi.encodeWithSelector(0x095ea7b3, spender, value);
        (success, bytes memory returndata) = token.call{accounts: _buildAccountMeta(token, spender)}(encodedCall);
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

    function _allowance(address token, address owner, address spender) private view returns (uint256) {
        bytes memory encodedCall = abi.encodeWithSelector(0xdd62ed3e, owner, spender);
        (bool success, bytes memory returndata) = token.staticcall{accounts: _buildAccountMeta(token)}(encodedCall);
        require(success, "SafeERC20: low-level static call failed");
        return abi.decode(returndata, (uint256));
    }

    function _isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _buildAccountMeta(address token, address spender) private pure returns (AccountMeta[] memory) {
        AccountMeta[] memory metas = new AccountMeta[](2);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: spender, is_signer: false, is_writable: true});
        return metas;
    }

    function _buildAccountMeta(address token, address from, address to) private pure returns (AccountMeta[] memory) {
        AccountMeta[] memory metas = new AccountMeta[](3);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: from, is_signer: false, is_writable: true});
        metas[2] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        return metas;
    }

    function _buildAccountMeta(address token) private pure returns (AccountMeta[] memory) {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: false});
        return metas;
    }
}