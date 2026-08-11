// SPDX-License-Identifier: ekubo-license-v1.eth
pragma solidity =0.8.33;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {Router} from "./Router.sol";
import {ICore, PoolKey} from "./interfaces/ICore.sol";
import {PoolState} from "./types/poolState.sol";
import {PoolBalanceUpdate} from "./types/poolBalanceUpdate.sol";
import {SwapParameters} from "./types/swapParameters.sol";
import {FlashAccountantLib} from "./libraries/FlashAccountantLib.sol";
import {CoreLib} from "./libraries/CoreLib.sol";

/// @title Oracla Router
/// @notice Router that forwards swaps on Oracla extension pools so protocol fees are applied.
contract OraclaRouter is Router {
    using FlashAccountantLib for *;
    using CoreLib for *;

    address public immutable ORACLA;

    constructor(ICore core, address oracla) Router(core) {
        ORACLA = oracla;
    }

    function _swap(uint256 value, PoolKey memory poolKey, SwapParameters params)
        internal
        override
        returns (PoolBalanceUpdate balanceUpdate, PoolState stateAfter)
    {
        if (poolKey.config.extension() != ORACLA) {
            (balanceUpdate, stateAfter) = CORE.swap(value, poolKey, params.withDefaultSqrtRatioLimit());
        } else {
            (balanceUpdate, stateAfter) = abi.decode(
                CORE.forward(ORACLA, abi.encode(poolKey, params.withDefaultSqrtRatioLimit())),
                (PoolBalanceUpdate, PoolState)
            );
            if (value != 0) {
                SafeTransferLib.safeTransferETH(address(CORE), value);
            }
        }
    }
}
