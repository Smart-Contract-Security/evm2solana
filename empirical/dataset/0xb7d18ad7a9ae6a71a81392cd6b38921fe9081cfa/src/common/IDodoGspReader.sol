// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DoDoGspResponse} from "../types/response.sol";

interface IDodoGspReader {
    function dodoGspPoolInfo(address pool) external view returns (DoDoGspResponse memory response);
}
