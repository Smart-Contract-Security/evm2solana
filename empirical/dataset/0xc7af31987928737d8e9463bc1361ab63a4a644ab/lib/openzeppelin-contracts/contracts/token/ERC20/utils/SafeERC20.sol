// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _call(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _call(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        _call(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        safeApprove(token, spender, 0);
        safeApprove(token, spender, value);
    }

    function _call(IERC20 token, bytes memory data) private {
        (bool ok, bytes memory ret) = address(token).call(data);
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "SafeERC20: failed");
    }
}
