// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ICurveStableReader.sol";
import "../types/request.sol";
import "../types/response.sol";
import "./libs/CurvePoolLib.sol";
import "./libs/CurveFactoryLib.sol";

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