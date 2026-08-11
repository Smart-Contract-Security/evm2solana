// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "./IERC20.sol";
import {IAdapter} from "./IAdapter.sol";

/// @title AdapterSwap
/// @notice Atomically routes a "transfer token -> sell" swap through a
///         DODO-style adapter in a single transaction, for both sides of a
///         pool (sellBase / sellQuote).
/// @dev    This is the piece Multicall3 could not do: the adapter computes the
///         swap from the tokens it *currently holds*, so the input token must
///         be moved into the adapter and the swap triggered in the same call
///         frame. Because the caller (an EOA) can only make one external call,
///         this helper contract performs both steps.
///
///         The caller must first `approve(address(AdapterSwap), amount)` on the
///         input token so this contract can pull the funds via `transferFrom`.
contract AdapterSwap {
    /// @notice Sell the pool's BASE token: pull `amount` of `sellToken` from the
    ///         caller into `adapter`, then trigger `sellBase`. Output -> `to`.
    function sellBase(
        address sellToken,
        address adapter,
        uint256 amount,
        address to,
        address pool,
        bytes calldata moreInfo
    ) external {
        _fund(sellToken, adapter, amount);
        IAdapter(adapter).sellBase(to, pool, moreInfo);
    }

    /// @notice Sell the pool's QUOTE token: pull `amount` of `sellToken` from the
    ///         caller into `adapter`, then trigger `sellQuote`. Output -> `to`.
    function sellQuote(
        address sellToken,
        address adapter,
        uint256 amount,
        address to,
        address pool,
        bytes calldata moreInfo
    ) external {
        _fund(sellToken, adapter, amount);
        IAdapter(adapter).sellQuote(to, pool, moreInfo);
    }

    /// @dev Move `amount` of `token` straight from the caller into `adapter`.
    ///      Requires the caller to have approved this contract beforehand.
    ///      Uses a safe transferFrom so non-standard tokens that return no data
    ///      (e.g. USDT) are handled correctly.
    function _fund(address token, address adapter, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, adapter, amount)
        );
        require(
            ok && (ret.length == 0 || abi.decode(ret, (bool))),
            "AdapterSwap: transferFrom failed"
        );
    }
}
