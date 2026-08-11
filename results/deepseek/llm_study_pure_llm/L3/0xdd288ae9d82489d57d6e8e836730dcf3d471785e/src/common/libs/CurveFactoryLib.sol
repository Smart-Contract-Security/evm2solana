// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CurveFactoryRequest, Dex} from "../../types/request.sol";
import {CurveStableResponseV3, CurveCryptoResponseV2} from "../../types/response.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CurveStablePool} from "../../abis/curve_stable_pool.sol";
import {CurveStableFactory} from "../../abis/curve_stable_factory.sol";
import {CurveMetaRegistry} from "../../abis/curve_meta_registry.sol";
import {CurveCryptoPool} from "../../abis/curve_crypto_pool.sol";
import {CurvePoolLib} from "./CurvePoolLib.sol";

/// @dev Curve 稳定池详情 + curveCryptoPoolInfoV2
library CurveFactoryLib {
    function curveStablePoolInfoNgByMeta(CurveFactoryRequest calldata params)
        private
        view
        returns (CurveStableResponseV3 memory response)
    {
        CurveStablePool pool = CurveStablePool(params.pool);
        CurveMetaRegistry metaRegistry = CurveMetaRegistry(params.metaRegistry);
        bool isMetaPool = metaRegistry.is_meta(params.pool);
        uint256 nCoins = metaRegistry.get_n_coins(params.pool);
        address[8] memory coins = metaRegistry.get_coins(params.pool);
        uint256[8] memory balances = metaRegistry.get_balances(params.pool);
        uint256[] memory rates = pool.stored_rates();

        response.tokens = new address[](nCoins);
        response.balances = new uint256[](nCoins);
        response.names = new string[](nCoins);
        response.symbols = new string[](nCoins);
        response.decimals = new uint256[](nCoins);
        response.assetTypes = new uint256[](nCoins);
        response.storeRates = new uint256[](nCoins);

        for (uint256 i = 0; i < nCoins; i++) {
            address token = coins[i];
            response.tokens[i] = token;
            response.balances[i] = balances[i];
            response.storeRates[i] = rates[i];
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
            address lpToken = metaRegistry.get_lp_token(params.pool);
            address baseAddr = metaRegistry.get_base_pool(params.pool);
            response.metaPool.basePoolAddr = baseAddr;

            uint256 baseN = metaRegistry.get_n_coins(baseAddr);
            response.metaPool.nCoins = baseN;

            address[8] memory baseCoins = metaRegistry.get_coins(baseAddr);
            uint256[8] memory baseBalances = metaRegistry.get_balances(baseAddr);

            CurveStablePool basePool = CurveStablePool(baseAddr);
            response.metaPool.ng = false;
            try basePool.D_ma_time() returns (uint256) {
                response.metaPool.ng = true;
            } catch {
                response.metaPool.ng = false;
            }

            response.metaPool.balances = new uint256[](baseN);
            response.metaPool.decimals = new uint256[](baseN);
            response.metaPool.StoredRates = new uint256[](baseN);
            response.metaPool.tokens = new address[](baseN);
            response.metaPool.names = new string[](baseN);
            response.metaPool.symbols = new string[](baseN);

            for (uint256 i = 0; i < baseN; i++) {
                address token = baseCoins[i];
                response.metaPool.balances[i] = baseBalances[i];
                response.metaPool.tokens[i] = token;

                if (token != CurvePoolLib.NATIVE_TOKEN) {
                    ERC20 tokenContract = ERC20(token);
                    response.metaPool.decimals[i] = uint256(tokenContract.decimals());
                    response.metaPool.names[i] = tokenContract.name();
                    response.metaPool.symbols[i] = tokenContract.symbol();
                } else {
                    response.metaPool.decimals[i] = 18;
                    response.metaPool.names[i] = "Ether";
                    response.metaPool.symbols[i] = "ETH";
                    response.metaPool.tokens[i] = address(0);
                }
            }

            response.metaPool.lpToken = lpToken;
            response.metaPool.fee = basePool.fee();
            response.metaPool.totalSupply = ERC20(lpToken).totalSupply();

            try basePool.future_A_time() returns (uint256 futureATime) {
                response.metaPool.futureATime = futureATime;
            } catch {
                response.metaPool.futureATime = 0;
            }

            try basePool.future_A() returns (uint256 futureA) {
                response.metaPool.futureA = futureA;
            } catch {
                response.metaPool.futureA = 0;
            }

            try basePool.initial_A_time() returns (uint256 initialATime) {
                response.metaPool.initialATime = initialATime;
            } catch {
                response.metaPool.initialATime = 0;
            }

            try basePool.initial_A() returns (uint256 initialA) {
                response.metaPool.initialA = initialA;
            } catch {
                response.metaPool.initialA = 0;
            }

            if (response.metaPool.ng) {
                response.metaPool.StoredRates = basePool.stored_rates();
                response.metaPool.OffPegFeeMultiplier = basePool.offpeg_fee_multiplier();
            }
        } else {
            address[10] memory handle = metaRegistry.get_registry_handlers_from_pool(params.pool);
            address poolFactory = metaRegistry.get_base_registry(handle[0]);
            CurveStableFactory factoryNg = CurveStableFactory(poolFactory);
            response.assetTypes = factoryNg.get_pool_asset_types(params.pool);

            response.metaPool.balances = new uint256[](0);
            response.metaPool.decimals = new uint256[](0);
            response.metaPool.tokens = new address[](0);
            response.metaPool.names = new string[](0);
            response.metaPool.symbols = new string[](0);
            response.metaPool.StoredRates = new uint256[](0);
        }
        response.blockNumber = block.number;
        response.isMeta = isMetaPool;
        response.nCoins = nCoins;
        response.fee = pool.fee();
        response.adminFee = pool.admin_fee();
        response.offPegFeeMultiplier = pool.offpeg_fee_multiplier();

        try pool.future_A_time() returns (uint256 futureATime) {
            response.futureATime = futureATime;
        } catch {
            response.futureATime = 0;
        }

        try pool.future_A() returns (uint256 futureA) {
            response.futureA = futureA;
        } catch {
            response.futureA = 0;
        }

        try pool.initial_A_time() returns (uint256 initialATime) {
            response.initialATime = initialATime;
        } catch {
            response.initialATime = 0;
        }

        try pool.initial_A() returns (uint256 initialA) {
            response.initialA = initialA;
        } catch {
            response.initialA = 0;
        }

        return response;
    }

    function curveStablePoolInfoV1ByMeta(CurveFactoryRequest calldata params)
        private
        view
        returns (CurveStableResponseV3 memory response)
    {
        CurveStablePool pool = CurveStablePool(params.pool);
        response.blockNumber = block.number;
        CurveMetaRegistry metaRegistry = CurveMetaRegistry(params.metaRegistry);
        bool isMetaPool = metaRegistry.is_meta(params.pool);
        response.isMeta = isMetaPool;
        uint256 nCoin = metaRegistry.get_n_coins(params.pool);
        response.nCoins = nCoin;

        response.tokens = new address[](nCoin);
        response.balances = new uint256[](nCoin);
        response.names = new string[](nCoin);
        response.symbols = new string[](nCoin);
        response.decimals = new uint256[](nCoin);
        response.assetTypes = new uint256[](nCoin);
        response.storeRates = new uint256[](nCoin);
        address[8] memory coins = metaRegistry.get_coins(params.pool);
        uint256[8] memory balances = metaRegistry.get_balances(params.pool);

        for (uint256 i = 0; i < nCoin; i++) {
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
        (bool success, bytes memory result) = params.pool.staticcall(callData);

        if (success && result.length >= 32) {
            CurvePoolLib.fillStoreRatesFromBytes(result, nCoin, response.storeRates);
        } else {
            for (uint256 i = 0; i < nCoin; i++) {
                if (response.decimals[i] <= 36) {
                    response.storeRates[i] = 10 ** (36 - response.decimals[i]);
                } else {
                    response.storeRates[i] = 1;
                }
            }
        }

        if (isMetaPool) {
            address lpToken = metaRegistry.get_lp_token(params.pool);
            address baseAddr = metaRegistry.get_base_pool(params.pool);
            response.metaPool.basePoolAddr = baseAddr;
            CurveStablePool basePool = CurveStablePool(baseAddr);
            uint256 baseN = metaRegistry.get_n_coins(baseAddr);
            uint256[8] memory baseBalances = metaRegistry.get_balances(baseAddr);
            address[8] memory baseCoins = metaRegistry.get_coins(baseAddr);
            response.metaPool.balances = new uint256[](baseN);
            response.metaPool.decimals = new uint256[](baseN);
            response.metaPool.tokens = new address[](baseN);
            response.metaPool.names = new string[](baseN);
            response.metaPool.symbols = new string[](baseN);

            for (uint256 i = 0; i < baseN; i++) {
                address token = baseCoins[i];
                response.metaPool.balances[i] = baseBalances[i];
                response.metaPool.tokens[i] = token;

                if (token != CurvePoolLib.NATIVE_TOKEN) {
                    ERC20 tokenContract = ERC20(token);
                    response.metaPool.decimals[i] = uint256(tokenContract.decimals());
                    response.metaPool.names[i] = tokenContract.name();
                    response.metaPool.symbols[i] = tokenContract.symbol();
                } else {
                    response.metaPool.decimals[i] = 18;
                    response.metaPool.names[i] = "Ether";
                    response.metaPool.symbols[i] = "ETH";
                    response.metaPool.tokens[i] = address(0);
                }
            }
            response.metaPool.nCoins = baseN;
            response.metaPool.lpToken = lpToken;
            response.metaPool.fee = basePool.fee();
            response.metaPool.totalSupply = ERC20(lpToken).totalSupply();

            try basePool.future_A_time() returns (uint256 futureATime) {
                response.metaPool.futureATime = futureATime;
            } catch {
                response.metaPool.futureATime = 0;
            }

            try basePool.future_A() returns (uint256 futureA) {
                response.metaPool.futureA = futureA;
            } catch {
                response.metaPool.futureA = 0;
            }

            try basePool.initial_A_time() returns (uint256 initialATime) {
                response.metaPool.initialATime = initialATime;
            } catch {
                response.metaPool.initialATime = 0;
            }

            try basePool.initial_A() returns (uint256 initialA) {
                response.metaPool.initialA = initialA;
            } catch {
                response.metaPool.initialA = 0;
            }
        } else {
            response.metaPool.balances = new uint256[](0);
            response.metaPool.decimals = new uint256[](0);
            response.metaPool.tokens = new address[](0);
            response.metaPool.names = new string[](0);
            response.metaPool.symbols = new string[](0);
            response.metaPool.StoredRates = new uint256[](0);
        }

        response.fee = pool.fee();
        response.adminFee = pool.admin_fee();

        try pool.offpeg_fee_multiplier() returns (uint256 offPegFee) {
            response.offPegFeeMultiplier = offPegFee;
        } catch {
            response.offPegFeeMultiplier = 0;
        }

        try pool.future_A_time() returns (uint256 futureATime) {
            response.futureATime = futureATime;
        } catch {
            response.futureATime = 0;
        }

        try pool.future_A() returns (uint256 futureA) {
            response.futureA = futureA;
        } catch {
            response.futureA = 0;
        }

        try pool.initial_A_time() returns (uint256 initialATime) {
            response.initialATime = initialATime;
        } catch {
            response.initialATime = 0;
        }

        try pool.initial_A() returns (uint256 initialA) {
            response.initialA = initialA;
        } catch {
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
        CurveStablePool pool = CurveStablePool(params.pool);
        response.aPrecision = 1;
        try pool.A_precise() returns (uint256 aPrecise) {
            try pool.A() returns (uint256 a) {
                if (a > 0) {
                    response.aPrecision = aPrecise / a;
                }
            } catch {}
        } catch {}

        uint256 nCoins = response.nCoins;
        response.actualBalances = new uint256[](nCoins);
        for (uint256 i = 0; i < nCoins; i++) {
            address token = response.tokens[i];
            if (token != address(0) && token != CurvePoolLib.NATIVE_TOKEN) {
                ERC20 tokenContract = ERC20(token);
                response.actualBalances[i] = tokenContract.balanceOf(params.pool);
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
        CurveCryptoPool pool = CurveCryptoPool(params.pool);
        CurveMetaRegistry metaRegistry = CurveMetaRegistry(params.metaRegistry);
        uint256 nCoins = metaRegistry.get_n_coins(params.pool);
        address[8] memory tempTokens = metaRegistry.get_coins(params.pool);
        uint256[8] memory balances = metaRegistry.get_balances(params.pool);

        response.nCoins = nCoins;
        response.blockNumber = block.number;

        response.tokens = new address[](nCoins);
        response.decimals = new uint256[](nCoins);
        response.balances = new uint256[](nCoins);
        response.names = new string[](nCoins);
        response.symbols = new string[](nCoins);

        for (uint256 i = 0; i < nCoins; i++) {
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

        response.initialAGamma = pool.initial_A_gamma();
        response.futureAGamma = pool.future_A_gamma();
        response.initialAGammaTime = pool.initial_A_gamma_time();
        response.futureAGammaTime = pool.future_A_gamma_time();

        response.priceScales = new uint256[](nCoins - 1);
        if (nCoins == 2) {
            response.priceScales[0] = pool.price_scale();
        } else {
            for (uint256 i = 0; i < nCoins - 1; i++) {
                response.priceScales[i] = pool.price_scale(i);
            }
        }

        response.D = pool.D();
        response.feeGamma = pool.fee_gamma();
        response.midFee = pool.mid_fee();
        response.outFee = pool.out_fee();

        response.isKilled = false;
        if (params.dex == Dex.CURVE_CRYPTO) {
            (bool success, bytes memory data) = address(pool).staticcall(abi.encodeWithSignature("is_killed()"));
            if (success && data.length == 32) {
                response.isKilled = abi.decode(data, (bool));
            }
        }

        response.actualBalances = new uint256[](nCoins);
        for (uint256 i = 0; i < nCoins; i++) {
            address token = response.tokens[i];
            if (token != address(0) && token != CurvePoolLib.NATIVE_TOKEN) {
                ERC20 tokenContract = ERC20(token);
                response.actualBalances[i] = tokenContract.balanceOf(params.pool);
            } else {
                response.actualBalances[i] = 0;
            }
        }

        // 3币种池（tricrypto）固定使用 CryptoMath，isStableMath = false
        // 2币种池从 pool.MATH() 获取 math 合约地址，再通过 newton_y 探测判断：
        //   TwocryptoMath (2币种 CryptoMath) 有公开 @external newton_y → 合法参数调用成功 → isStableMath=false
        //   StableMath 无 newton_y (@external) → Vyper fallback revert → isStableMath=true
        //   TricryptoMath 的 _newton_y 是内部方法，无公开 selector → 同样 revert
        //
        //   探测参数选平衡池合法值（在 MIN_A/MAX_A/MIN_GAMMA/MAX_GAMMA/D 约束范围内）：
        //     ANN=400000, gamma=1e14, x=[1e18,1e18], D=2e18, i=0
        //   源码约束: MIN_A=4000, MAX_A=40000000, MIN_GAMMA=1e10, MAX_GAMMA=1.99e17, D∈[1e17,1e33]
        //   以上参数对 TwocryptoMath 必然返回成功，对 StableMath 必然 revert。
        response.isStableMath = false;
        if (nCoins == 2) {
            (bool mathSuccess, bytes memory mathData) = address(pool).staticcall(abi.encodeWithSignature("MATH()"));
            if (mathSuccess && mathData.length == 32) {
                address mathAddr = abi.decode(mathData, (address));
                if (mathAddr != address(0)) {
                    // newton_y(uint256 ANN, uint256 gamma, uint256[2] x, uint256 D, uint256 i)
                    // selector = keccak256("newton_y(uint256,uint256,uint256[2],uint256,uint256)") = 0x29fcfcf2
                    bytes memory probeInput = abi.encodeWithSelector(
                        bytes4(0x29fcfcf2),
                        uint256(400000),          // ANN: 4*1e4*10 (within [4000, 40000000])
                        uint256(1e14),            // gamma: 1e14  (within [1e10, 1.99e17])
                        uint256(1e18),            // x[0]: 1e18
                        uint256(1e18),            // x[1]: 1e18
                        uint256(2e18),            // D: 2e18 (within [1e17, 1e33])
                        uint256(0)                // i: 0
                    );
                    (bool newtonSuccess,) = mathAddr.staticcall(probeInput);
                    // TwocryptoMath: newton_y exists and params are valid → success → isStableMath=false
                    // StableMath: no newton_y selector → Vyper fallback revert → isStableMath=true
                    response.isStableMath = !newtonSuccess;
                }
            }
        }

        return response;
    }
}