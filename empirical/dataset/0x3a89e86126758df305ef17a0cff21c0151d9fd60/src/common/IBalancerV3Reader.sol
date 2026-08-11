// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BalancerV3BasePoolRequest} from "../types/request.sol";
import {
    BalancerV3BasePoolResponse,
    BalancerV3BasePoolResponseV2,
    BalancerV3PoolType,
    BalancerV3PoolFeatures,
    BalancerV3Erc4626BalanceResponse
} from "../types/response.sol";

interface IBalancerV3Reader {
    function balancerV3PoolType(BalancerV3BasePoolRequest calldata request) external view returns (BalancerV3PoolType);
    function balancerV3PoolFeatures(BalancerV3BasePoolRequest calldata request) external view returns (BalancerV3PoolFeatures memory features);
    function balancerV3BasePoolInfoV2(BalancerV3BasePoolRequest calldata request) external view returns (BalancerV3BasePoolResponseV2 memory response);
    function batchBalancerV3Erc4626Balance(address vault, address[] calldata rateProviders)
        external
        view
        returns (BalancerV3Erc4626BalanceResponse memory response);
}