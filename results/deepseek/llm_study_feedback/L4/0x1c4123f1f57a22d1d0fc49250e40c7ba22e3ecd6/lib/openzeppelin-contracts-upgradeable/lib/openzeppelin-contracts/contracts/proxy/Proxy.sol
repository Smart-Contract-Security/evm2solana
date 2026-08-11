// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract Proxy {
    function _delegate(address implementation) internal virtual {
        // Solang for Solana does not support inline assembly.
        // Delegatecall is not natively supported on Solana.
        // This function must be overridden or implemented using Solana-specific cross-program invocation.
        revert("delegatecall not supported");
    }

    function _implementation() internal view virtual returns (address);

    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    // Solana does not support receive() functions.
    // Use a regular fallback function instead.
    fallback() external virtual {
        _fallback();
    }
}