// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CurveLlamaLendResponse} from "../types/response.sol";

interface ICurveLlamaLendReader {
    function curveLlamaLendPoolInfo(address poolAddr, int256 maxBandWindow)
        external
        view
        returns (CurveLlamaLendResponse memory);

    // 批量读取所有 factory 的 AMM 地址
    function curveLlamaLendFactoryAmms(address[] calldata factories)
        external
        view
        returns (address[] memory amms);
}
