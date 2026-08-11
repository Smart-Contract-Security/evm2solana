import 'solana';

library ChainConfig {
    uint64 internal constant ETHEREUM_MAINNET_CHAIN_ID = 1;
    uint64 internal constant BASE_CHAIN_ID = 8453;

    address internal constant ETHEREUM_POOL_MANAGER = address"0x000000000004444c5dc75cB358380D2e3dE08A90";
    address internal constant BASE_POOL_MANAGER = address"0x498581fF718922c3f8e6A244956aF099B2652b2b";

    function isSupportedChain(uint64 chainId) internal pure returns (bool) {
        return chainId == ETHEREUM_MAINNET_CHAIN_ID || chainId == BASE_CHAIN_ID;
    }

    function poolManager(uint64 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET_CHAIN_ID) return ETHEREUM_POOL_MANAGER;
        if (chainId == BASE_CHAIN_ID) return BASE_POOL_MANAGER;
        revert("UnsupportedChain");
    }
}