// SPDX-License-Identifier: UNLICENSED

import {CurveFactoryRequest, Dex} from "../../types/request.sol";
import {CurveFilterResponseV2, CurveBaseInfoResponse} from "../../types/response.sol";
import {CurveStablePool} from "../../abis/curve_stable_pool.sol";
import {CurveStableFactory} from "../../abis/curve_stable_factory.sol";
import {CurveMetaRegistry} from "../../abis/curve_meta_registry.sol";

library CurvePoolLib {
    address internal constant NATIVE_TOKEN = address(0);

    function getNonNativeTokenInfo(address token)
        internal
        view
        returns (uint64 decimals, string memory name, string memory symbol)
    {
        (bool success, bytes memory ret) = token.call{accounts: []}(abi.encodeWithSignature("decimals()"));
        if (success && ret.length >= 32) {
            decimals = uint64(abi.decode(ret, (uint256)));
        }
        (success, ret) = token.call{accounts: []}(abi.encodeWithSignature("name()"));
        if (success) {
            name = abi.decode(ret, (string));
        }
        (success, ret) = token.call{accounts: []}(abi.encodeWithSignature("symbol()"));
        if (success) {
            symbol = abi.decode(ret, (string));
        }
    }

    function fillStoreRatesFromBytes(bytes memory result, uint64 nCoins, uint64[] memory storeRates) internal pure {
        if (result.length < 32) return;
        uint64 rateCount = uint64(result.length / 32);
        for (uint64 i = 0; i < nCoins && i < rateCount; i++) {
            uint256 rate = uint256(bytes32(slice(result, (i + 1) * 32, 32)));
            storeRates[i] = uint64(rate);
        }
    }

    function slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory) {
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = data[start + i];
        }
        return b;
    }

    function curveBaseInfo(CurveFactoryRequest calldata params) internal view returns (CurveBaseInfoResponse memory response) {
        response.isRegistered = false;
        response.isMeta = false;
        response.nCoins = 0;
        response.baseNCoins = 0;
        address metaRegistry = params.metaRegistry;
        (bool success, bytes memory ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("is_registered(address)", params.pool));
        bool registry = false;
        if (success && ret.length >= 32) {
            registry = abi.decode(ret, (bool));
        }
        if (registry) {
            response.isRegistered = registry;
            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_n_coins(address)", params.pool));
            uint64 nCoins = 0;
            if (success && ret.length >= 32) {
                nCoins = uint64(abi.decode(ret, (uint256)));
            }
            response.nCoins = nCoins;
            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("is_meta(address)", params.pool));
            bool meta = false;
            if (success && ret.length >= 32) {
                meta = abi.decode(ret, (bool));
            }
            if (meta) {
                response.isMeta = true;
                (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_base_pool(address)", params.pool));
                address basePool = address(0);
                if (success && ret.length >= 32) {
                    basePool = abi.decode(ret, (address));
                }
                (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_n_coins(address)", basePool));
                uint64 baseNCoins = 0;
                if (success && ret.length >= 32) {
                    baseNCoins = uint64(abi.decode(ret, (uint256)));
                }
                response.baseNCoins = baseNCoins;
            }
        }
        return response;
    }

    function curveFactory(CurveFactoryRequest calldata params) internal view returns (address) {
        address metaRegistry = params.metaRegistry;
        (bool success, bytes memory ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("is_registered(address)", params.pool));
        if (!success || ret.length < 32) {
            return address(0);
        }
        bool isRegistered = abi.decode(ret, (bool));
        if (!isRegistered) {
            return address(0);
        }
        address[10] memory registries;
        (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_registry_handlers_from_pool(address)", params.pool));
        if (!success || ret.length < 320) {
            return address(0);
        }
        registries = abi.decode(ret, (address[10]));
        if (registries[0] == address(0)) {
            return address(0);
        } else {
            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_base_registry(address)", registries[0]));
            if (success && ret.length >= 32) {
                return abi.decode(ret, (address));
            }
            return address(0);
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
        address metaRegistry = params.metaRegistry;

        bool registry = false;
        (bool success, bytes memory ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("is_registered(address)", params.pool));
        if (success && ret.length >= 32) {
            registry = abi.decode(ret, (bool));
        }
        if (registry) {
            response.isRegistered = true;
            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_n_coins(address)", params.pool));
            uint64 nCoins = 0;
            if (success && ret.length >= 32) {
                nCoins = uint64(abi.decode(ret, (uint256)));
            }
            response.nCoins = nCoins;
            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("is_meta(address)", params.pool));
            bool meta = false;
            if (success && ret.length >= 32) {
                meta = abi.decode(ret, (bool));
            }
            if (meta) {
                response.isMeta = true;
                (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_base_pool(address)", params.pool));
                address basePool = address(0);
                if (success && ret.length >= 32) {
                    basePool = abi.decode(ret, (address));
                }
                (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_n_coins(address)", basePool));
                uint64 baseNCoins = 0;
                if (success && ret.length >= 32) {
                    baseNCoins = uint64(abi.decode(ret, (uint256)));
                }
                response.baseNCoins = baseNCoins;
            }

            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_registry_handlers_from_pool(address)", params.pool));
            address[10] memory registryHandler;
            if (success && ret.length >= 320) {
                registryHandler = abi.decode(ret, (address[10]));
            }
            (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_base_registry(address)", registryHandler[0]));
            address baseRegistry = address(0);
            if (success && ret.length >= 32) {
                baseRegistry = abi.decode(ret, (address));
            }

            if (Dex.CURVE_STABLE_NG == params.dex) {
                (success, ret) = baseRegistry.call{accounts: []}(abi.encodeWithSignature("get_pool_asset_types(address)", params.pool));
                if (success && ret.length >= 32) {
                    response.assetTypes = abi.decode(ret, (uint64));
                }
            } else {
                (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_coins(address)", params.pool));
                address[8] memory coins;
                if (success && ret.length >= 256) {
                    coins = abi.decode(ret, (address[8]));
                }
                (success, ret) = metaRegistry.call{accounts: []}(abi.encodeWithSignature("get_underlying_coins(address)", params.pool));
                address[8] memory underlyingCoins;
                if (success && ret.length >= 256) {
                    underlyingCoins = abi.decode(ret, (address[8]));
                }
                for (uint64 i = 0; i < nCoins; i++) {
                    if (coins[i] != underlyingCoins[i]) {
                        response.isLeading = true;
                        break;
                    }
                }
            }
            response.factory = baseRegistry;

            (success, ret) = params.pool.call{accounts: []}(abi.encodeWithSignature("oracle()"));
            if (success && ret.length >= 32) {
                address oracleAddr = abi.decode(ret, (address));
                if (oracleAddr != address(0)) {
                    response.oracle = oracleAddr;
                }
            }
        }

        if (response.isRegistered) {
            response.storeRates = new uint64[](response.nCoins);
            bytes memory callData = abi.encodeWithSignature("stored_rates()");
            (success, ret) = params.pool.call{accounts: []}(callData);

            if (success && ret.length >= 32) {
                fillStoreRatesFromBytes(ret, response.nCoins, response.storeRates);
            }
        }
        return response;
    }
}