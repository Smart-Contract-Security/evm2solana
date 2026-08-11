// SPDX-License-Identifier: UNLICENSED

import {CurveFactoryRequest, Dex} from "../../types/request.sol";
import {CurveStableResponseV3, CurveCryptoResponseV2} from "../../types/response.sol";
import {CurvePoolLib} from "./CurvePoolLib.sol";

library CurveFactoryLib {
    function curveStablePoolInfoNgByMeta(CurveFactoryRequest calldata params)
        private
        view
        returns (CurveStableResponseV3 memory response)
    {
        address pool = params.pool;
        address metaRegistry = params.metaRegistry;

        (bool isMetaSuccess, bytes memory isMetaData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("is_meta(address)", params.pool));
        bool isMetaPool = isMetaSuccess && isMetaData.length >= 32 ? abi.decode(isMetaData, (bool)) : false;

        (bool nCoinsSuccess, bytes memory nCoinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_n_coins(address)", params.pool));
        uint64 nCoins = nCoinsSuccess && nCoinsData.length >= 32 ? uint64(abi.decode(nCoinsData, (uint256))) : 0;

        (bool coinsSuccess, bytes memory coinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_coins(address)", params.pool));
        address[8] memory coins;
        if (coinsSuccess && coinsData.length >= 256) {
            coins = abi.decode(coinsData, (address[8]));
        }

        uint64[8] memory balances;
        {
            (bool balSuccess, bytes memory balData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_balances(address)", params.pool));
            if (balSuccess && balData.length >= 256) {
                uint256[8] memory balances256 = abi.decode(balData, (uint256[8]));
                for (uint64 i = 0; i < 8; i++) {
                    balances[i] = uint64(balances256[i]);
                }
            }
        }

        uint64[] memory rates;
        {
            (bool ratesSuccess, bytes memory ratesData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("stored_rates()"));
            if (ratesSuccess && ratesData.length >= 32) {
                uint256[] memory rates256 = abi.decode(ratesData, (uint256[]));
                rates = new uint64[](rates256.length);
                for (uint64 i = 0; i < rates256.length; i++) {
                    rates[i] = uint64(rates256[i]);
                }
            } else {
                rates = new uint64[](0);
            }
        }

        response.tokens = new address[](nCoins);
        response.balances = new uint64[](nCoins);
        response.names = new string[](nCoins);
        response.symbols = new string[](nCoins);
        response.decimals = new uint64[](nCoins);
        response.assetTypes = new uint64[](nCoins);
        response.storeRates = new uint64[](nCoins);

        for (uint64 i = 0; i < nCoins; i++) {
            address token = coins[i];
            response.tokens[i] = token;
            response.balances[i] = balances[i];
            if (i < rates.length) {
                response.storeRates[i] = rates[i];
            }
            if (token != CurvePoolLib.NATIVE_TOKEN) {
                (response.decimals[i], response.names[i], response.symbols[i]) =
                    CurvePoolLib.getNonNativeTokenInfo(token);
            } else {
                response.tokens[i] = address(0);
                response.decimals[i] = 18;
                response.names[i] = "Ether";
                response.symbols[i] = "ETH";
            }
        }

        if (isMetaPool) {
            (bool lpSuccess, bytes memory lpData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_lp_token(address)", params.pool));
            address lpToken = lpSuccess && lpData.length >= 32 ? abi.decode(lpData, (address)) : address(0);

            (bool baseSuccess, bytes memory baseData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_base_pool(address)", params.pool));
            address baseAddr = baseSuccess && baseData.length >= 32 ? abi.decode(baseData, (address)) : address(0);

            response.metaPool.basePoolAddr = baseAddr;

            (bool baseNSuccess, bytes memory baseNData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_n_coins(address)", baseAddr));
            uint64 baseN = baseNSuccess && baseNData.length >= 32 ? uint64(abi.decode(baseNData, (uint256))) : 0;
            response.metaPool.nCoins = baseN;

            (bool baseCoinsSuccess, bytes memory baseCoinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_coins(address)", baseAddr));
            address[8] memory baseCoins;
            if (baseCoinsSuccess && baseCoinsData.length >= 256) {
                baseCoins = abi.decode(baseCoinsData, (address[8]));
            }

            uint64[8] memory baseBalances;
            {
                (bool baseBalSuccess, bytes memory baseBalData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_balances(address)", baseAddr));
                if (baseBalSuccess && baseBalData.length >= 256) {
                    uint256[8] memory baseBalances256 = abi.decode(baseBalData, (uint256[8]));
                    for (uint64 i = 0; i < 8; i++) {
                        baseBalances[i] = uint64(baseBalances256[i]);
                    }
                }
            }

            response.metaPool.ng = false;
            (bool dMaTimeSuccess, bytes memory dMaTimeResult) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("D_ma_time()"));
            if (dMaTimeSuccess && dMaTimeResult.length >= 32) {
                response.metaPool.ng = true;
            } else {
                response.metaPool.ng = false;
            }

            response.metaPool.balances = new uint64[](baseN);
            response.metaPool.decimals = new uint64[](baseN);
            response.metaPool.StoredRates = new uint64[](baseN);
            response.metaPool.tokens = new address[](baseN);
            response.metaPool.names = new string[](baseN);
            response.metaPool.symbols = new string[](baseN);

            for (uint64 i = 0; i < baseN; i++) {
                address token = baseCoins[i];
                response.metaPool.balances[i] = baseBalances[i];
                response.metaPool.tokens[i] = token;

                if (token != CurvePoolLib.NATIVE_TOKEN) {
                    (bool decSuccess, bytes memory decData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("decimals()"));
                    if (decSuccess && decData.length >= 32) {
                        response.metaPool.decimals[i] = uint64(abi.decode(decData, (uint256)));
                    }
                    (bool nameSuccess, bytes memory nameData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("name()"));
                    if (nameSuccess && nameData.length > 0) {
                        response.metaPool.names[i] = string(nameData);
                    }
                    (bool symSuccess, bytes memory symData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("symbol()"));
                    if (symSuccess && symData.length > 0) {
                        response.metaPool.symbols[i] = string(symData);
                    }
                } else {
                    response.metaPool.decimals[i] = 18;
                    response.metaPool.names[i] = "Ether";
                    response.metaPool.symbols[i] = "ETH";
                    response.metaPool.tokens[i] = address(0);
                }
            }

            response.metaPool.lpToken = lpToken;
            (bool feeSuccess, bytes memory feeData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("fee()"));
            response.metaPool.fee = feeSuccess && feeData.length >= 32 ? uint64(abi.decode(feeData, (uint256))) : 0;

            (bool tsSuccess, bytes memory tsData) = lpToken.call{accounts: tx.accounts}(abi.encodeWithSignature("totalSupply()"));
            if (tsSuccess && tsData.length >= 32) {
                response.metaPool.totalSupply = uint64(abi.decode(tsData, (uint256)));
            }

            (bool futATimeSuccess, bytes memory futATimeData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A_time()"));
            if (futATimeSuccess && futATimeData.length >= 32) {
                response.metaPool.futureATime = uint64(abi.decode(futATimeData, (uint256)));
            } else {
                response.metaPool.futureATime = 0;
            }

            (bool futASuccess, bytes memory futAData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A()"));
            if (futASuccess && futAData.length >= 32) {
                response.metaPool.futureA = uint64(abi.decode(futAData, (uint256)));
            } else {
                response.metaPool.futureA = 0;
            }

            (bool initATimeSuccess, bytes memory initATimeData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A_time()"));
            if (initATimeSuccess && initATimeData.length >= 32) {
                response.metaPool.initialATime = uint64(abi.decode(initATimeData, (uint256)));
            } else {
                response.metaPool.initialATime = 0;
            }

            (bool initASuccess, bytes memory initAData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A()"));
            if (initASuccess && initAData.length >= 32) {
                response.metaPool.initialA = uint64(abi.decode(initAData, (uint256)));
            } else {
                response.metaPool.initialA = 0;
            }

            if (response.metaPool.ng) {
                (bool storedRatesSuccess, bytes memory storedRatesData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("stored_rates()"));
                if (storedRatesSuccess && storedRatesData.length >= 32) {
                    uint256[] memory storedRates256 = abi.decode(storedRatesData, (uint256[]));
                    response.metaPool.StoredRates = new uint64[](storedRates256.length);
                    for (uint64 i = 0; i < storedRates256.length; i++) {
                        response.metaPool.StoredRates[i] = uint64(storedRates256[i]);
                    }
                }
                (bool offpegSuccess, bytes memory offpegData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("offpeg_fee_multiplier()"));
                response.metaPool.OffPegFeeMultiplier = offpegSuccess && offpegData.length >= 32 ? uint64(abi.decode(offpegData, (uint256))) : 0;
            }
        } else {
            (bool handleSuccess, bytes memory handleData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_registry_handlers_from_pool(address)", params.pool));
            address[10] memory handle;
            if (handleSuccess && handleData.length >= 320) {
                handle = abi.decode(handleData, (address[10]));
            }
            (bool regSuccess, bytes memory regData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_base_registry(address)", handle[0]));
            address poolFactory = regSuccess && regData.length >= 32 ? abi.decode(regData, (address)) : address(0);

            (bool assetTypesSuccess, bytes memory assetTypesData) = poolFactory.call{accounts: tx.accounts}(abi.encodeWithSignature("get_pool_asset_types(address)", params.pool));
            if (assetTypesSuccess && assetTypesData.length >= 32) {
                uint256[] memory assetTypes256 = abi.decode(assetTypesData, (uint256[]));
                response.assetTypes = new uint64[](assetTypes256.length);
                for (uint64 i = 0; i < assetTypes256.length; i++) {
                    response.assetTypes[i] = uint64(assetTypes256[i]);
                }
            }

            response.metaPool.balances = new uint64[](0);
            response.metaPool.decimals = new uint64[](0);
            response.metaPool.tokens = new address[](0);
            response.metaPool.names = new string[](0);
            response.metaPool.symbols = new string[](0);
            response.metaPool.StoredRates = new uint64[](0);
        }
        response.blockNumber = uint64(block.number);
        response.isMeta = isMetaPool;
        response.nCoins = nCoins;

        (bool feeSuccess2, bytes memory feeData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("fee()"));
        response.fee = feeSuccess2 && feeData2.length >= 32 ? uint64(abi.decode(feeData2, (uint256))) : 0;

        (bool adminFeeSuccess, bytes memory adminFeeData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("admin_fee()"));
        response.adminFee = adminFeeSuccess && adminFeeData.length >= 32 ? uint64(abi.decode(adminFeeData, (uint256))) : 0;

        (bool offPegSuccess2, bytes memory offPegData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("offpeg_fee_multiplier()"));
        response.offPegFeeMultiplier = offPegSuccess2 && offPegData2.length >= 32 ? uint64(abi.decode(offPegData2, (uint256))) : 0;

        (bool futATimeSuccess2, bytes memory futATimeData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A_time()"));
        if (futATimeSuccess2 && futATimeData2.length >= 32) {
            response.futureATime = uint64(abi.decode(futATimeData2, (uint256)));
        } else {
            response.futureATime = 0;
        }

        (bool futASuccess2, bytes memory futAData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A()"));
        if (futASuccess2 && futAData2.length >= 32) {
            response.futureA = uint64(abi.decode(futAData2, (uint256)));
        } else {
            response.futureA = 0;
        }

        (bool initATimeSuccess2, bytes memory initATimeData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A_time()"));
        if (initATimeSuccess2 && initATimeData2.length >= 32) {
            response.initialATime = uint64(abi.decode(initATimeData2, (uint256)));
        } else {
            response.initialATime = 0;
        }

        (bool initASuccess2, bytes memory initAData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A()"));
        if (initASuccess2 && initAData2.length >= 32) {
            response.initialA = uint64(abi.decode(initAData2, (uint256)));
        } else {
            response.initialA = 0;
        }

        return response;
    }

    function curveStablePoolInfoV1ByMeta(CurveFactoryRequest calldata params)
        private
        view
        returns (CurveStableResponseV3 memory response)
    {
        address pool = params.pool;
        response.blockNumber = uint64(block.number);
        address metaRegistry = params.metaRegistry;

        (bool isMetaSuccess, bytes memory isMetaData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("is_meta(address)", params.pool));
        bool isMetaPool = isMetaSuccess && isMetaData.length >= 32 ? abi.decode(isMetaData, (bool)) : false;
        response.isMeta = isMetaPool;

        (bool nCoinsSuccess, bytes memory nCoinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_n_coins(address)", params.pool));
        uint64 nCoin = nCoinsSuccess && nCoinsData.length >= 32 ? uint64(abi.decode(nCoinsData, (uint256))) : 0;
        response.nCoins = nCoin;

        response.tokens = new address[](nCoin);
        response.balances = new uint64[](nCoin);
        response.names = new string[](nCoin);
        response.symbols = new string[](nCoin);
        response.decimals = new uint64[](nCoin);
        response.assetTypes = new uint64[](nCoin);
        response.storeRates = new uint64[](nCoin);

        (bool coinsSuccess, bytes memory coinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_coins(address)", params.pool));
        address[8] memory coins;
        if (coinsSuccess && coinsData.length >= 256) {
            coins = abi.decode(coinsData, (address[8]));
        }

        uint64[8] memory balances;
        {
            (bool balSuccess, bytes memory balData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_balances(address)", params.pool));
            if (balSuccess && balData.length >= 256) {
                uint256[8] memory balances256 = abi.decode(balData, (uint256[8]));
                for (uint64 i = 0; i < 8; i++) {
                    balances[i] = uint64(balances256[i]);
                }
            }
        }

        for (uint64 i = 0; i < nCoin; i++) {
            address token = coins[i];
            response.balances[i] = balances[i];
            if (token != CurvePoolLib.NATIVE_TOKEN) {
                response.tokens[i] = token;
                (response.decimals[i], response.names[i], response.symbols[i]) =
                    CurvePoolLib.getNonNativeTokenInfo(token);
            } else {
                response.decimals[i] = 18;
                response.names[i] = "Ether";
                response.symbols[i] = "ETH";
                response.tokens[i] = address(0);
            }
        }

        bytes memory callData = abi.encodeWithSignature("stored_rates()");
        (bool success, bytes memory result) = params.pool.call{accounts: tx.accounts}(callData);

        if (success && result.length >= 32) {
            CurvePoolLib.fillStoreRatesFromBytes(result, nCoin, response.storeRates);
        } else {
            for (uint64 i = 0; i < nCoin; i++) {
                if (response.decimals[i] <= 36) {
                    response.storeRates[i] = uint64(10 ** (36 - response.decimals[i]));
                } else {
                    response.storeRates[i] = 1;
                }
            }
        }

        if (isMetaPool) {
            (bool lpSuccess, bytes memory lpData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_lp_token(address)", params.pool));
            address lpToken = lpSuccess && lpData.length >= 32 ? abi.decode(lpData, (address)) : address(0);

            (bool baseSuccess, bytes memory baseData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_base_pool(address)", params.pool));
            address baseAddr = baseSuccess && baseData.length >= 32 ? abi.decode(baseData, (address)) : address(0);

            response.metaPool.basePoolAddr = baseAddr;

            (bool baseNSuccess, bytes memory baseNData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_n_coins(address)", baseAddr));
            uint64 baseN = baseNSuccess && baseNData.length >= 32 ? uint64(abi.decode(baseNData, (uint256))) : 0;

            uint64[8] memory baseBalances;
            {
                (bool baseBalSuccess, bytes memory baseBalData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_balances(address)", baseAddr));
                if (baseBalSuccess && baseBalData.length >= 256) {
                    uint256[8] memory baseBalances256 = abi.decode(baseBalData, (uint256[8]));
                    for (uint64 i = 0; i < 8; i++) {
                        baseBalances[i] = uint64(baseBalances256[i]);
                    }
                }
            }

            (bool baseCoinsSuccess, bytes memory baseCoinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_coins(address)", baseAddr));
            address[8] memory baseCoins;
            if (baseCoinsSuccess && baseCoinsData.length >= 256) {
                baseCoins = abi.decode(baseCoinsData, (address[8]));
            }

            response.metaPool.balances = new uint64[](baseN);
            response.metaPool.decimals = new uint64[](baseN);
            response.metaPool.tokens = new address[](baseN);
            response.metaPool.names = new string[](baseN);
            response.metaPool.symbols = new string[](baseN);

            for (uint64 i = 0; i < baseN; i++) {
                address token = baseCoins[i];
                response.metaPool.balances[i] = baseBalances[i];
                response.metaPool.tokens[i] = token;

                if (token != CurvePoolLib.NATIVE_TOKEN) {
                    (bool decSuccess, bytes memory decData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("decimals()"));
                    if (decSuccess && decData.length >= 32) {
                        response.metaPool.decimals[i] = uint64(abi.decode(decData, (uint256)));
                    }
                    (bool nameSuccess, bytes memory nameData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("name()"));
                    if (nameSuccess && nameData.length > 0) {
                        response.metaPool.names[i] = string(nameData);
                    }
                    (bool symSuccess, bytes memory symData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("symbol()"));
                    if (symSuccess && symData.length > 0) {
                        response.metaPool.symbols[i] = string(symData);
                    }
                } else {
                    response.metaPool.decimals[i] = 18;
                    response.metaPool.names[i] = "Ether";
                    response.metaPool.symbols[i] = "ETH";
                    response.metaPool.tokens[i] = address(0);
                }
            }
            response.metaPool.nCoins = baseN;
            response.metaPool.lpToken = lpToken;

            (bool feeSuccess, bytes memory feeData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("fee()"));
            response.metaPool.fee = feeSuccess && feeData.length >= 32 ? uint64(abi.decode(feeData, (uint256))) : 0;

            (bool tsSuccess, bytes memory tsData) = lpToken.call{accounts: tx.accounts}(abi.encodeWithSignature("totalSupply()"));
            if (tsSuccess && tsData.length >= 32) {
                response.metaPool.totalSupply = uint64(abi.decode(tsData, (uint256)));
            }

            (bool futATimeSuccess, bytes memory futATimeData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A_time()"));
            if (futATimeSuccess && futATimeData.length >= 32) {
                response.metaPool.futureATime = uint64(abi.decode(futATimeData, (uint256)));
            } else {
                response.metaPool.futureATime = 0;
            }

            (bool futASuccess, bytes memory futAData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A()"));
            if (futASuccess && futAData.length >= 32) {
                response.metaPool.futureA = uint64(abi.decode(futAData, (uint256)));
            } else {
                response.metaPool.futureA = 0;
            }

            (bool initATimeSuccess, bytes memory initATimeData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A_time()"));
            if (initATimeSuccess && initATimeData.length >= 32) {
                response.metaPool.initialATime = uint64(abi.decode(initATimeData, (uint256)));
            } else {
                response.metaPool.initialATime = 0;
            }

            (bool initASuccess, bytes memory initAData) = baseAddr.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A()"));
            if (initASuccess && initAData.length >= 32) {
                response.metaPool.initialA = uint64(abi.decode(initAData, (uint256)));
            } else {
                response.metaPool.initialA = 0;
            }
        } else {
            response.metaPool.balances = new uint64[](0);
            response.metaPool.decimals = new uint64[](0);
            response.metaPool.tokens = new address[](0);
            response.metaPool.names = new string[](0);
            response.metaPool.symbols = new string[](0);
            response.metaPool.StoredRates = new uint64[](0);
        }

        (bool feeSuccess2, bytes memory feeData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("fee()"));
        response.fee = feeSuccess2 && feeData2.length >= 32 ? uint64(abi.decode(feeData2, (uint256))) : 0;

        (bool adminFeeSuccess, bytes memory adminFeeData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("admin_fee()"));
        response.adminFee = adminFeeSuccess && adminFeeData.length >= 32 ? uint64(abi.decode(adminFeeData, (uint256))) : 0;

        (bool offPegSuccess, bytes memory offPegData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("offpeg_fee_multiplier()"));
        if (offPegSuccess && offPegData.length >= 32) {
            response.offPegFeeMultiplier = uint64(abi.decode(offPegData, (uint256)));
        } else {
            response.offPegFeeMultiplier = 0;
        }

        (bool futATimeSuccess2, bytes memory futATimeData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A_time()"));
        if (futATimeSuccess2 && futATimeData2.length >= 32) {
            response.futureATime = uint64(abi.decode(futATimeData2, (uint256)));
        } else {
            response.futureATime = 0;
        }

        (bool futASuccess2, bytes memory futAData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A()"));
        if (futASuccess2 && futAData2.length >= 32) {
            response.futureA = uint64(abi.decode(futAData2, (uint256)));
        } else {
            response.futureA = 0;
        }

        (bool initATimeSuccess2, bytes memory initATimeData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A_time()"));
        if (initATimeSuccess2 && initATimeData2.length >= 32) {
            response.initialATime = uint64(abi.decode(initATimeData2, (uint256)));
        } else {
            response.initialATime = 0;
        }

        (bool initASuccess2, bytes memory initAData2) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A()"));
        if (initASuccess2 && initAData2.length >= 32) {
            response.initialA = uint64(abi.decode(initAData2, (uint256)));
        } else {
            response.initialA = 0;
        }

        return response;
    }

    function curveStablePoolInfoV3(CurveFactoryRequest calldata params)
        internal
        view
        returns (CurveStableResponseV3 memory response)
    {
        if (params.dex == Dex.CURVE_STABLE_NG) {
            response = curveStablePoolInfoNgByMeta(params);
        } else {
            response = curveStablePoolInfoV1ByMeta(params);
        }
        address pool = params.pool;
        response.aPrecision = 1;
        (bool aPreciseSuccess, bytes memory aPreciseData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("A_precise()"));
        if (aPreciseSuccess && aPreciseData.length >= 32) {
            uint256 aPrecise = abi.decode(aPreciseData, (uint256));
            (bool aSuccess, bytes memory aData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("A()"));
            if (aSuccess && aData.length >= 32) {
                uint256 a = abi.decode(aData, (uint256));
                if (a > 0) {
                    response.aPrecision = uint64(aPrecise / a);
                }
            }
        }

        uint64 nCoins = response.nCoins;
        response.actualBalances = new uint64[](nCoins);
        for (uint64 i = 0; i < nCoins; i++) {
            address token = response.tokens[i];
            if (token != address(0) && token != CurvePoolLib.NATIVE_TOKEN) {
                (bool balSuccess, bytes memory balData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("balanceOf(address)", params.pool));
                if (balSuccess && balData.length >= 32) {
                    response.actualBalances[i] = uint64(abi.decode(balData, (uint256)));
                } else {
                    response.actualBalances[i] = 0;
                }
            } else {
                response.actualBalances[i] = 0;
            }
        }

        return response;
    }

    function curveCryptoPoolInfoV2(CurveFactoryRequest calldata params)
        internal
        view
        returns (CurveCryptoResponseV2 memory response)
    {
        address pool = params.pool;
        address metaRegistry = params.metaRegistry;

        (bool nCoinsSuccess, bytes memory nCoinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_n_coins(address)", params.pool));
        uint64 nCoins = nCoinsSuccess && nCoinsData.length >= 32 ? uint64(abi.decode(nCoinsData, (uint256))) : 0;

        (bool coinsSuccess, bytes memory coinsData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_coins(address)", params.pool));
        address[8] memory tempTokens;
        if (coinsSuccess && coinsData.length >= 256) {
            tempTokens = abi.decode(coinsData, (address[8]));
        }

        uint64[8] memory balances;
        {
            (bool balSuccess, bytes memory balData) = metaRegistry.call{accounts: tx.accounts}(abi.encodeWithSignature("get_balances(address)", params.pool));
            if (balSuccess && balData.length >= 256) {
                uint256[8] memory balances256 = abi.decode(balData, (uint256[8]));
                for (uint64 i = 0; i < 8; i++) {
                    balances[i] = uint64(balances256[i]);
                }
            }
        }

        response.nCoins = nCoins;
        response.blockNumber = uint64(block.number);

        response.tokens = new address[](nCoins);
        response.decimals = new uint64[](nCoins);
        response.balances = new uint64[](nCoins);
        response.names = new string[](nCoins);
        response.symbols = new string[](nCoins);

        for (uint64 i = 0; i < nCoins; i++) {
            response.tokens[i] = tempTokens[i];
            response.balances[i] = balances[i];
            if (tempTokens[i] != CurvePoolLib.NATIVE_TOKEN) {
                (response.decimals[i], response.names[i], response.symbols[i]) =
                    CurvePoolLib.getNonNativeTokenInfo(tempTokens[i]);
            } else {
                response.decimals[i] = 18;
                response.names[i] = "Ether";
                response.symbols[i] = "ETH";
                response.tokens[i] = address(0);
            }
        }

        (bool initAGammaSuccess, bytes memory initAGammaData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A_gamma()"));
        response.initialAGamma = initAGammaSuccess && initAGammaData.length >= 32 ? uint64(abi.decode(initAGammaData, (uint256))) : 0;

        (bool futAGammaSuccess, bytes memory futAGammaData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A_gamma()"));
        response.futureAGamma = futAGammaSuccess && futAGammaData.length >= 32 ? uint64(abi.decode(futAGammaData, (uint256))) : 0;

        (bool initAGammaTimeSuccess, bytes memory initAGammaTimeData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("initial_A_gamma_time()"));
        response.initialAGammaTime = initAGammaTimeSuccess && initAGammaTimeData.length >= 32 ? uint64(abi.decode(initAGammaTimeData, (uint256))) : 0;

        (bool futAGammaTimeSuccess, bytes memory futAGammaTimeData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("future_A_gamma_time()"));
        response.futureAGammaTime = futAGammaTimeSuccess && futAGammaTimeData.length >= 32 ? uint64(abi.decode(futAGammaTimeData, (uint256))) : 0;

        response.priceScales = new uint64[](nCoins - 1);
        if (nCoins == 2) {
            (bool psSuccess, bytes memory psData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("price_scale()"));
            response.priceScales[0] = psSuccess && psData.length >= 32 ? uint64(abi.decode(psData, (uint256))) : 0;
        } else {
            for (uint64 i = 0; i < nCoins - 1; i++) {
                (bool psSuccess, bytes memory psData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("price_scale(uint256)", uint256(i)));
                response.priceScales[i] = psSuccess && psData.length >= 32 ? uint64(abi.decode(psData, (uint256))) : 0;
            }
        }

        (bool dSuccess, bytes memory dData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("D()"));
        response.D = dSuccess && dData.length >= 32 ? uint64(abi.decode(dData, (uint256))) : 0;

        (bool feeGammaSuccess, bytes memory feeGammaData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("fee_gamma()"));
        response.feeGamma = feeGammaSuccess && feeGammaData.length >= 32 ? uint64(abi.decode(feeGammaData, (uint256))) : 0;

        (bool midFeeSuccess, bytes memory midFeeData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("mid_fee()"));
        response.midFee = midFeeSuccess && midFeeData.length >= 32 ? uint64(abi.decode(midFeeData, (uint256))) : 0;

        (bool outFeeSuccess, bytes memory outFeeData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("out_fee()"));
        response.outFee = outFeeSuccess && outFeeData.length >= 32 ? uint64(abi.decode(outFeeData, (uint256))) : 0;

        response.isKilled = false;
        if (params.dex == Dex.CURVE_CRYPTO) {
            (bool success, bytes memory data) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("is_killed()"));
            if (success && data.length == 32) {
                response.isKilled = abi.decode(data, (bool));
            }
        }

        response.actualBalances = new uint64[](nCoins);
        for (uint64 i = 0; i < nCoins; i++) {
            address token = response.tokens[i];
            if (token != address(0) && token != CurvePoolLib.NATIVE_TOKEN) {
                (bool balSuccess, bytes memory balData) = token.call{accounts: tx.accounts}(abi.encodeWithSignature("balanceOf(address)", params.pool));
                if (balSuccess && balData.length >= 32) {
                    response.actualBalances[i] = uint64(abi.decode(balData, (uint256)));
                } else {
                    response.actualBalances[i] = 0;
                }
            } else {
                response.actualBalances[i] = 0;
            }
        }

        response.isStableMath = false;
        if (nCoins == 2) {
            (bool mathSuccess, bytes memory mathData) = pool.call{accounts: tx.accounts}(abi.encodeWithSignature("MATH()"));
            if (mathSuccess && mathData.length == 32) {
                address mathAddr = abi.decode(mathData, (address));
                if (mathAddr != address(0)) {
                    bytes memory probeInput = abi.encodeWithSelector(
                        bytes4(0x29fcfcf2),
                        uint256(400000),
                        uint256(1e14),
                        uint256(1e18),
                        uint256(1e18),
                        uint256(2e18),
                        uint256(0)
                    );
                    (bool newtonSuccess,) = mathAddr.call{accounts: tx.accounts}(probeInput);
                    response.isStableMath = !newtonSuccess;
                }
            }
        }

        return response;
    }
}