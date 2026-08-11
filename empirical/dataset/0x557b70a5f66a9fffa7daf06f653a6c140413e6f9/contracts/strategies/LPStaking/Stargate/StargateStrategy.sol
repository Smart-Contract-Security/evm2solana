// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { BaseTransfers } from "../../../base/BaseTransfers/v1/BaseTransfers.sol";

import {
    CoreAccessControlConfig,
    CoreSwapConfig,
    CoreFeesConfig,
    LPStakingConfig
} from "../../../modules/LPStakingStrategy/v1/LPStakingStrategy.sol";
import { StargateBase, StargateConfig } from "./StargateBase.sol";
import { IStargateRouter } from "../../../protocols/stargate/Interfaces.sol";

import { DefinitiveAssets, IERC20 } from "../../../core/libraries/DefinitiveAssets.sol";

contract StargateStrategy is StargateBase, BaseTransfers {
    using DefinitiveAssets for IERC20;

    constructor(
        CoreAccessControlConfig memory coreAccessControlConfig,
        CoreSwapConfig memory coreSwapConfig,
        CoreFeesConfig memory coreFeesConfig,
        LPStakingConfig memory lpConfig,
        StargateConfig memory strategyConfig
    ) StargateBase(coreAccessControlConfig, coreSwapConfig, coreFeesConfig, lpConfig, strategyConfig) {}

    function _addLiquidity(
        uint256[] calldata amounts,
        uint256 // unused param `minAmount`
    ) internal override {
        address FIRST_LP_UNDERLYING_TOKEN = LP_UNDERLYING_TOKENS[0];
        address mLP_DEPOSIT_POOL = LP_DEPOSIT_POOL;
        DefinitiveAssets.validateBalance(FIRST_LP_UNDERLYING_TOKEN, amounts[0]);
        IERC20(FIRST_LP_UNDERLYING_TOKEN).resetAndSafeIncreaseAllowance(address(this), mLP_DEPOSIT_POOL, amounts[0]);
        IStargateRouter(mLP_DEPOSIT_POOL).addLiquidity(cfg.depositTokenPoolId, amounts[0], address(this));
    }
}
