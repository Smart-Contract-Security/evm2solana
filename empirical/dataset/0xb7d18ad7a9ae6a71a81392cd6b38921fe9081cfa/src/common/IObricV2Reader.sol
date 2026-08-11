// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ObricV2Response} from "../types/response.sol";

interface IObricV2Reader {
    function obricV2PoolInfo(address poolAddr) external view returns (ObricV2Response memory response);
}
