// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BalancerV1PoolRequest} from "../types/request.sol";
import {BalancerV1PoolResponse} from "../types/response.sol";

interface IBalancerV1Reader {
    function balancerV1PoolInfo(BalancerV1PoolRequest calldata params)
        external
        view
        returns (BalancerV1PoolResponse memory response);

    /// @return true if pool was created by the given BFactory
    function isBalancerV1Pool(address pool, address factory) external view returns (bool);
}
