// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Solang on Solana does not support importing external Solidity files directly.
// We define minimal interfaces and types inline to replace the imports.

// Minimal ERC20 interface
interface IERC20 {
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

// Minimal CurveMetaRegistry interface
interface ICurveMetaRegistry {
    function is_registered(address pool) external view returns (bool);
    function get_n_coins(address pool) external view returns (uint256);
    function is_meta(address pool) external view returns (bool);
    function get_base_pool(address pool) external view returns (address);
    function get_registry_handlers_from_pool(address pool) external view returns (address[10] memory);
    function get_base_registry(address handler) external view returns (address);
    function get_coins(address pool) external view returns (address[8] memory);
    function get_underlying_coins(address pool) external view returns (address[8] memory);
}

// Minimal CurveStablePool interface
interface ICurveStablePool {
    function oracle() external view returns (address);
}

// Minimal CurveStableFactory interface
interface ICurveStableFactory {
    function get_pool_asset_types(address pool) external view returns (uint256[8] memory);
}

// Enum Dex (from request.sol)
enum Dex {
    CURVE_STABLE_NG,
    OTHER
}

// Struct CurveFactoryRequest (from request.sol)
struct CurveFactoryRequest {
    address pool;
    address metaRegistry;
    Dex dex;
}

// Struct CurveBaseInfoResponse (from response.sol)
struct CurveBaseInfoResponse {
    bool isRegistered;
    bool isMeta;
    uint256 nCoins;
    uint256 baseNCoins;
}

// Struct CurveFilterResponseV2 (from response.sol)
struct CurveFilterResponseV2 {
    bool isRegistered;
    bool isMeta;
    bool isLeading;
    uint256 nCoins;
    uint256 baseNCoins;
    address oracle;
    address factory;
    uint256[8] assetTypes;
    uint256[] storeRates;
}

/// @dev Curve 稳定读：代币辅助 + curveBaseInfo / curveFactory / curveStableFactoryV2
library CurvePoolLib {
    address internal constant NATIVE_TOKEN = address(0);

    function getNonNativeTokenInfo(address token)
        internal
        view
        returns (uint256 decimals, string memory name, string memory symbol)
    {
        decimals = uint256(IERC20(token).decimals());
        name = IERC20(token).name();
        symbol = IERC20(token).symbol();
    }

    function fillStoreRatesFromBytes(bytes memory result, uint256 nCoins, uint256[] memory storeRates) internal pure {
        if (result.length < 32) return;
        uint256 rateCount = result.length / 32;
        for (uint256 i = 0; i < nCoins && i < rateCount; i++) {
            uint256 rate = 0;
            uint256 offset = (i + 1) * 32;
            for (uint256 j = 0; j < 32; j++) {
                if (offset + j < result.length) {
                    rate |= uint256(uint8(result[offset + j])) << (8 * (31 - j));
                }
            }
            storeRates[i] = rate;
        }
    }

    function curveBaseInfo(CurveFactoryRequest calldata params) internal view returns (CurveBaseInfoResponse memory response) {
        response.isRegistered = false;
        response.isMeta = false;
        response.nCoins = 0;
        response.baseNCoins = 0;
        bool registry = ICurveMetaRegistry(params.metaRegistry).is_registered(params.pool);
        if (registry) {
            response.isRegistered = registry;
            uint256 nCoins = ICurveMetaRegistry(params.metaRegistry).get_n_coins(params.pool);
            response.nCoins = nCoins;
            bool meta = ICurveMetaRegistry(params.metaRegistry).is_meta(params.pool);
            if (meta) {
                response.isMeta = true;
                address basePool = ICurveMetaRegistry(params.metaRegistry).get_base_pool(params.pool);
                uint256 baseNCoins = ICurveMetaRegistry(params.metaRegistry).get_n_coins(basePool);
                response.baseNCoins = baseNCoins;
            }
        }
        return response;
    }

    function curveFactory(CurveFactoryRequest calldata params) internal view returns (address) {
        // Use interface calls instead of low-level staticcall
        bool isRegistered = ICurveMetaRegistry(params.metaRegistry).is_registered(params.pool);
        if (!isRegistered) {
            return address(0);
        }

        address[10] memory registries = ICurveMetaRegistry(params.metaRegistry).get_registry_handlers_from_pool(params.pool);
        if (registries[0] == address(0)) {
            return address(0);
        } else {
            return ICurveMetaRegistry(params.metaRegistry).get_base_registry(registries[0]);
        }
    }

    function curveStableFactoryV2(CurveFactoryRequest calldata params)
        internal
        view
        returns (CurveFilterResponseV2 memory response)
    {
        response.isRegistered = false;
        response.isMeta = false;
        response.isLeading = false;
        response.nCoins = 0;
        response.baseNCoins = 0;
        response.oracle = address(0);
        response.factory = address(0);

        bool registry = ICurveMetaRegistry(params.metaRegistry).is_registered(params.pool);

        if (registry) {
            response.isRegistered = true;
            uint256 nCoins = ICurveMetaRegistry(params.metaRegistry).get_n_coins(params.pool);
            response.nCoins = nCoins;
            bool meta = ICurveMetaRegistry(params.metaRegistry).is_meta(params.pool);
            if (meta) {
                response.isMeta = true;
                address basePool = ICurveMetaRegistry(params.metaRegistry).get_base_pool(params.pool);
                uint256 baseNCoins = ICurveMetaRegistry(params.metaRegistry).get_n_coins(basePool);
                response.baseNCoins = baseNCoins;
            }

            address[10] memory registryHandler = ICurveMetaRegistry(params.metaRegistry).get_registry_handlers_from_pool(params.pool);
            address baseRegistry = ICurveMetaRegistry(params.metaRegistry).get_base_registry(registryHandler[0]);
            response.factory = baseRegistry;

            if (Dex.CURVE_STABLE_NG == params.dex) {
                response.assetTypes = ICurveStableFactory(baseRegistry).get_pool_asset_types(params.pool);
            } else {
                address[8] memory coins = ICurveMetaRegistry(params.metaRegistry).get_coins(params.pool);
                address[8] memory underlyingCoins = ICurveMetaRegistry(params.metaRegistry).get_underlying_coins(params.pool);
                for (uint256 i = 0; i < nCoins; i++) {
                    if (coins[i] != underlyingCoins[i]) {
                        response.isLeading = true;
                        break;
                    }
                }
            }

            // Use interface call instead of low-level staticcall
            try ICurveStablePool(params.pool).oracle() returns (address oracleAddr) {
                if (oracleAddr != address(0)) {
                    response.oracle = oracleAddr;
                }
            } catch {
                // oracle not available, leave as address(0)
            }
        }

        if (response.isRegistered) {
            response.storeRates = new uint256[](response.nCoins);
            // Use low-level call for stored_rates() since we don't have an interface for it
            bytes memory callData = abi.encodeWithSignature("stored_rates()");
            (bool callSuccess, bytes memory result) = address(params.pool).call(callData);

            if (callSuccess && result.length >= 32) {
                fillStoreRatesFromBytes(result, response.nCoins, response.storeRates);
            }
        }
        return response;
    }
}