// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MainnetAddresses
/// @notice Ethereum mainnet protocol addresses used by the FlashLoanRouter.
///         All addresses verified against Etherscan. Component 2 imports from here.
library MainnetAddresses {
    /// @notice Aave V3 Pool (InitializableImmutableAdminUpgradeabilityProxy)
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    /// @notice Aave V3 PoolAddressesProvider
    address internal constant AAVE_V3_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    /// @notice Wrapped Ether (WETH9)
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Uniswap V3 SwapRouter02
    address internal constant UNISWAP_V3_SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    /// @notice Uniswap V3 Factory
    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    /// @notice Balancer V2 Vault — flash-loan source for FlashLoanRouter v2 (PHY-118).
    ///         0 fee for USDC/USDT/DAI/WETH/WBTC at time of writing; verify at runtime
    ///         via ProtocolFeesCollector.getFlashLoanFeePercentage() before relying.
    address internal constant BALANCER_V2_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /// @notice Balancer V2 ProtocolFeesCollector — source of the flash-loan fee percentage
    ///         (scaled 1e18). Queried so v2 can reject fees above the 5 bps self-imposed cap.
    address internal constant BALANCER_V2_FEES_COLLECTOR = 0xce88686553686DA562CE7Cea497CE749DA109f9F;
}
