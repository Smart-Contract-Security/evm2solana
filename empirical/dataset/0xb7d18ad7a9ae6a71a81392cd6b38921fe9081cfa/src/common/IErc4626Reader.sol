// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Erc4626Response} from "../types/response.sol";

interface IErc4626Reader {
    function erc4626PoolInfo(address vault, address handler) external view returns (Erc4626Response memory result);
}
