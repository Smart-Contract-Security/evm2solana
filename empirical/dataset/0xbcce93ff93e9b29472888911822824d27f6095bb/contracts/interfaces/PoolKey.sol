// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Currency type wraps address; address(0) represents native ETH
type Currency is address;

/// @notice Library for Currency operations
library CurrencyLibrary {
    Currency public constant ADDRESS_ZERO = Currency.wrap(address(0));

    function isAddressZero(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == address(0);
    }

    function toId(Currency currency) internal pure returns (uint256) {
        return uint256(uint160(Currency.unwrap(currency)));
    }
}

/// @notice PoolId is a bytes32 hash of the PoolKey
type PoolId is bytes32;

/// @notice Identifies a Uniswap V4 pool
struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @notice Library for computing PoolId from PoolKey
library PoolIdLibrary {
    /// @notice Returns the key's PoolId (keccak256 hash of the struct)
    function toId(PoolKey memory poolKey) internal pure returns (PoolId) {
        return PoolId.wrap(keccak256(abi.encode(poolKey)));
    }
}
