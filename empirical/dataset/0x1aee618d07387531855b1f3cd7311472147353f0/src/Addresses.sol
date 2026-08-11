// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TokenFlow external mainnet addresses
/// @notice Single source of truth for Ethereum mainnet (chain ID 1) integrations. Verified via
///         https://developers.uniswap.org/contracts/v4/deployments at scaffold time.
///         Contracts depending on these MUST take them as constructor `immutable` params
///         (per `ARCHITECTURE.md` §9.12) — this file is only for deploy scripts and tests.
library Addresses {
    // Wrapped Ether
    address internal constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Uniswap V2 (used for V2-pool eligible-token swaps)
    address internal constant V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    // Uniswap V3 (used for V3-pool eligible-token swaps)
    address internal constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // TFLO/native-ETH V4 pool parameters — single Solidity source of truth (mirrored off-chain by
    // backend/app/constants.py:POOL_FEE_BPS; a guard test asserts the two agree). LaunchpadV4,
    // Deploy.s.sol and the fork-test base all read these instead of hard-coding the literals.
    uint24 internal constant TFLO_POOL_FEE = 50_000;    // 5% (V4 pip units, 1e6 = 100%)
    int24  internal constant TFLO_TICK_SPACING = 200;

    // Uniswap V4 (TFLO/native-ETH pair + V4-pool eligible-token swaps)
    address internal constant V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant V4_QUOTER = 0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;
    address internal constant V4_STATE_VIEW = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;

    // Universal Router (v2.5 — entry point for all swaps regardless of pool kind)
    address internal constant UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    // Permit2 (Universal Router moves user tokens via permit2)
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
}
