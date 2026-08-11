// SPDX-License-Identifier: UNLICENSED

import {ICurveStableReader} from "./ICurveStableReader.sol";
import {CurveFactoryRequest} from "../types/request.sol";
import {CurveFilterResponseV2, CurveStableResponseV3, CurveCryptoResponseV2, CurveBaseInfoResponse} from "../types/response.sol";

library CurvePoolLib {
    function curveBaseInfo(CurveFactoryRequest calldata params) external view returns (CurveBaseInfoResponse memory) {
        // Placeholder implementation
        revert();
    }

    function curveFactory(CurveFactoryRequest calldata params) external view returns (address) {
        // Placeholder implementation
        revert();
    }

    function curveStableFactoryV2(CurveFactoryRequest calldata params) external view returns (CurveFilterResponseV2 memory) {
        // Placeholder implementation
        revert();
    }
}

library CurveFactoryLib {
    function curveStablePoolInfoV3(CurveFactoryRequest calldata params) external view returns (CurveStableResponseV3 memory) {
        // Placeholder implementation
        revert();
    }

    function curveCryptoPoolInfoV2(CurveFactoryRequest calldata params) external view returns (CurveCryptoResponseV2 memory) {
        // Placeholder implementation
        revert();
    }
}

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