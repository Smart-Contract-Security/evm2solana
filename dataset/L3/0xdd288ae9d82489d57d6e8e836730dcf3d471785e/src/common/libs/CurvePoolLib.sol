// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CurveFactoryRequest, Dex} from "../../types/request.sol";
import {CurveFilterResponseV2, CurveBaseInfoResponse} from "../../types/response.sol";
import {CurveStablePool} from "../../abis/curve_stable_pool.sol";
import {CurveStableFactory} from "../../abis/curve_stable_factory.sol";
import {CurveMetaRegistry} from "../../abis/curve_meta_registry.sol";

/// @dev Curve 稳定读：代币辅助 + curveBaseInfo / curveFactory / curveStableFactoryV2
library CurvePoolLib {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function getNonNativeTokenInfo(address token)
        internal
        view
        returns (uint256 decimals, string memory name, string memory symbol)
    {
        ERC20 tokenContract = ERC20(token);
        decimals = uint256(tokenContract.decimals());
        name = tokenContract.name();
        symbol = tokenContract.symbol();
    }

    function fillStoreRatesFromBytes(bytes memory result, uint256 nCoins, uint256[] memory storeRates) internal pure {
        if (result.length < 32) return;
        uint256 rateCount = result.length / 32;
        for (uint256 i = 0; i < nCoins && i < rateCount; i++) {
            uint256 rate;
            assembly {
                rate := mload(add(result, mul(add(i, 1), 32)))
            }
            storeRates[i] = rate;
        }
    }

    function curveBaseInfo(CurveFactoryRequest calldata params) internal view returns (CurveBaseInfoResponse memory response) {
        response.isRegistered = false;
        response.isMeta = false;
        response.nCoins = 0;
        response.baseNCoins = 0;
        CurveMetaRegistry metaRegistry = CurveMetaRegistry(params.metaRegistry);
        bool registry = metaRegistry.is_registered(params.pool);
        if (registry) {
            response.isRegistered = registry;
            uint256 nCoins = metaRegistry.get_n_coins(params.pool);
            response.nCoins = nCoins;
            bool meta = metaRegistry.is_meta(params.pool);
            if (meta) {
                response.isMeta = true;
                address basePool = metaRegistry.get_base_pool(params.pool);
                uint256 baseNCoins = metaRegistry.get_n_coins(basePool);
                response.baseNCoins = baseNCoins;
            }
        }
        return response;
    }

    function curveFactory(CurveFactoryRequest calldata params) internal view returns (address) {
        CurveMetaRegistry metaRegistry = CurveMetaRegistry(params.metaRegistry);
        try metaRegistry.is_registered(params.pool) returns (bool isRegistered) {
            if (!isRegistered) {
                return address(0);
            }
        } catch {
            return address(0);
        }
        address[10] memory registries;
        try metaRegistry.get_registry_handlers_from_pool(params.pool) returns (address[10] memory _registries) {
            registries = _registries;
        } catch {
            return address(0);
        }
        if (registries[0] == address(0)) {
            return address(0);
        } else {
            return metaRegistry.get_base_registry(registries[0]);
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
        CurveMetaRegistry metaRegistry = CurveMetaRegistry(params.metaRegistry);

        bool registry;
        try metaRegistry.is_registered(params.pool) returns (bool _registry) {
            registry = _registry;
        } catch {
            registry =false;
        }
        if (registry) {
            response.isRegistered = true;
            uint256 nCoins = metaRegistry.get_n_coins(params.pool);
            response.nCoins = nCoins;
            bool meta = metaRegistry.is_meta(params.pool);
            if (meta) {
                response.isMeta = true;
                address basePool = metaRegistry.get_base_pool(params.pool);
                uint256 baseNCoins = metaRegistry.get_n_coins(basePool);
                response.baseNCoins = baseNCoins;
            }

            address[10] memory registryHandler = metaRegistry.get_registry_handlers_from_pool(params.pool);
            address baseRegistry = metaRegistry.get_base_registry(registryHandler[0]);

            if (Dex.CURVE_STABLE_NG == params.dex) {
                CurveStableFactory ngFactory = CurveStableFactory(baseRegistry);
                response.assetTypes = ngFactory.get_pool_asset_types(params.pool);
            } else {
                address[8] memory coins = metaRegistry.get_coins(params.pool);
                address[8] memory underlyingCoins = metaRegistry.get_underlying_coins(params.pool);
                for (uint256 i = 0; i < nCoins; i++) {
                    if (coins[i] != underlyingCoins[i]) {
                        response.isLeading = true;
                        break;
                    }
                }
            }
            response.factory = baseRegistry;

            CurveStablePool curvePool = CurveStablePool(params.pool);
            try curvePool.oracle() returns (address oracleAddr) {
                if (oracleAddr != address(0)) {
                    response.oracle = oracleAddr;
                }
            } catch {}
        }

        if (response.isRegistered) {
            response.storeRates = new uint256[](response.nCoins);
            bytes memory callData = abi.encodeWithSignature("stored_rates()");
            (bool success, bytes memory result) = params.pool.staticcall(callData);

            if (success && result.length >= 32) {
                fillStoreRatesFromBytes(result, response.nCoins, response.storeRates);
            }
        }
        return response;
    }
}
