// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DoDoV1Response} from "../types/response.sol";

interface IDodoV1Reader {
    function dodoV1PoolInfo(address pool) external view returns (DoDoV1Response memory response);
}
