import {CurveFactoryRequest} from "../types/request.sol";
import {CurveFilterResponseV2,CurveStableResponseV3,CurveCryptoResponseV2,CurveBaseInfoResponse} from "../types/response.sol";

interface ICurveStableReader {

   function curveBaseInfo(CurveFactoryRequest calldata params) external view returns (CurveBaseInfoResponse memory response);
   //判断pool是否属于curve协议，并返回对应的factory地址
   function curveFactory(CurveFactoryRequest calldata params) external view returns (address);
   //curve stable需要过滤的条件较多，合并一起，不仅返回factory还返回了其他判断条件
   function curveStableFactoryV2(CurveFactoryRequest calldata params) external view returns (CurveFilterResponseV2 memory response);
   //稳定币池子信息
   function curveStablePoolInfoV3(CurveFactoryRequest calldata params) external view returns (CurveStableResponseV3 memory response);
   //非稳定币池子信息
   function curveCryptoPoolInfoV2(CurveFactoryRequest calldata params) external view returns (CurveCryptoResponseV2 memory response);
}