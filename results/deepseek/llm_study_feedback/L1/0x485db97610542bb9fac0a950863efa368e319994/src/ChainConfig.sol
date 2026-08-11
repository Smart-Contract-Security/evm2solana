// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library ChainConfig {
    uint256 internal constant ETHEREUM_MAINNET_CHAIN_ID = 1;
    uint256 internal constant BASE_CHAIN_ID = 8453;

    bytes32 internal constant ETHEREUM_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    bytes32 internal constant BASE_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    function isSupportedChain(uint256 chainId) internal pure returns (bool) {
        return chainId == ETHEREUM_MAINNET_CHAIN_ID || chainId == BASE_CHAIN_ID;
    }

    function poolManager(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET_CHAIN_ID) return address(uint160(uint256(ETHEREUM_POOL_MANAGER)));
        if (chainId == BASE_CHAIN_ID) return address(uint160(uint256(BASE_POOL_MANAGER)));
        revert("UnsupportedChain");
    }
}