// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OriginArmRequest} from "../types/request.sol";
import {OriginArmResponse} from "../types/response.sol";

interface IOriginArmReader {
    function originArmPoolInfo(OriginArmRequest calldata params) external view returns (OriginArmResponse memory response);
}
