// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ICurveStableReader} from "./ICurveStableReader.sol";
import {CurveFactoryRequest} from "../types/request.sol";
import {CurveFilterResponseV2, CurveStableResponseV3, CurveCryptoResponseV2, CurveBaseInfoResponse} from "../types/response.sol";
import {CurvePoolLib} from "./libs/CurvePoolLib.sol";
import {CurveFactoryLib} from "./libs/CurveFactoryLib.sol";

/// @dev 其它链单合约部署：两个 library 见 `libs/`；Hyper 见 `hyper/curve/`
contract CurveStableReader is ICurveStableReader {
    function curveBaseInfo(CurveFactoryRequest calldata params) external view returns (CurveBaseInfoResponse memory response) {
        return CurvePoolLib.curveBaseInfo(params);
    }

    function curveFactory(CurveFactoryRequest calldata params) external view returns (address) {
        return CurvePoolLib.curveFactory(params);
    }

    function curveStableFactoryV2(CurveFactoryRequest calldata params)
        external
        view
        returns (CurveFilterResponseV2 memory response)
    {
        return CurvePoolLib.curveStableFactoryV2(params);
    }

    function curveStablePoolInfoV3(CurveFactoryRequest calldata params)
        external
        view
        returns (CurveStableResponseV3 memory response)
    {
        return CurveFactoryLib.curveStablePoolInfoV3(params);
    }

    function curveCryptoPoolInfoV2(CurveFactoryRequest calldata params)
        external
        view
        returns (CurveCryptoResponseV2 memory response)
    {
        return CurveFactoryLib.curveCryptoPoolInfoV2(params);
    }
}
