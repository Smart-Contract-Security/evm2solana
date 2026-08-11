// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import  "../types/response.sol";
import  "../types/request.sol";
import {IBalancerV3Reader} from "../common/IBalancerV3Reader.sol";
import {IBalancerV1Reader} from "../common/IBalancerV1Reader.sol";
import {IExtraPollingReader} from "../common/IExtraPollingReader.sol";
import {Erc4626Reader} from "../common/Erc4626Reader.sol";
import {ICurveLlamaLendReader} from "../common/ICurveLlamaLendReader.sol";
import {IOriginArmReader} from "../common/IOriginArmReader.sol";
import {IObricV2Reader} from "../common/IObricV2Reader.sol";
import {IDodoV1Reader} from "../common/IDodoV1Reader.sol";
import {IDodoGspReader} from "../common/IDodoGspReader.sol";
import {DoDoV1Response, DoDoGspResponse} from "../types/response.sol";
import {IEkuboReader} from "../common/IEkuboReader.sol";
import {ICurveStableReader} from "../common/ICurveStableReader.sol";

contract EthReader {
    address public immutable ethArchive = 0x9129c541c7f44931c088Bb01342890238ef31661;
    IBalancerV3Reader public constant balancerV3Reader = IBalancerV3Reader(0x9587BC1b021e8B7573dE4a51dE9A81Fbb334bb38);
    IBalancerV1Reader public constant balancerV1Reader = IBalancerV1Reader(0x2A7fDeaF6b01E6e9B6CDED7bBDCF77996008ceEA);
    IExtraPollingReader public constant extraPollingReader = IExtraPollingReader(0xEBcD721A3404CBd19C67236710028A74490C1fB1);
    Erc4626Reader public constant erc4626Reader = Erc4626Reader(0x39BF5Eb764ea179D6a0284D297a9019428FD541d);
    ICurveLlamaLendReader public constant curveLlamaLendReader = ICurveLlamaLendReader(0xdCd5443888f0cA76DEA9282C86Fbe97AAE6325A4);
    IOriginArmReader public constant originArmReader = IOriginArmReader(0xce2bAD12747Bec4cb3D6F2846ae2aBbf166d0d2E);
    IObricV2Reader public constant obricV2Reader = IObricV2Reader(0x7e0276195d8559Ad135867CA02BE60B00Ff47ED3);
    IDodoV1Reader public constant dodoV1Reader = IDodoV1Reader(0x0DC9A67ED334c312ad3BA0873D20c7a6347F212a);
    IDodoGspReader public constant dodoGspReader = IDodoGspReader(0xabC5d20D83879E1d77ef26628f93F7dfAA51A63B);
    IEkuboReader public constant ekuboReader = IEkuboReader(0xD97d6F98E032b7030E4dB4f6BDAD9f2F3eE805C1);

    ICurveStableReader public constant curveStableReader = ICurveStableReader(0xDD288aE9D82489d57D6e8E836730DCF3d471785e);

    function version() public pure returns (uint256) {
        return 21;
    }

    fallback() external payable {
        address _impl = ethArchive;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result case 0 { revert(0, returndatasize()) } default { return(0, returndatasize()) }
        }
    }

    function balancerV3PoolFeatures(BalancerV3BasePoolRequest calldata params) external view returns (BalancerV3PoolFeatures memory) {
        return balancerV3Reader.balancerV3PoolFeatures(params);
    }

    function balancerV3BasePoolInfoV2(BalancerV3BasePoolRequest calldata request) external view returns (BalancerV3BasePoolResponseV2 memory response) {
        return balancerV3Reader.balancerV3BasePoolInfoV2(request);
    }

    function batchBalancerV3Erc4626Balance(address vault, address[] calldata rateProviders) external view returns (BalancerV3Erc4626BalanceResponse memory response) {
        return balancerV3Reader.batchBalancerV3Erc4626Balance(vault, rateProviders);
    }

    function balancerV1PoolInfo(BalancerV1PoolRequest calldata params) external view returns (BalancerV1PoolResponse memory) {
        return balancerV1Reader.balancerV1PoolInfo(params);
    }

    function isBalancerV1Pool(address pool, address factory) external view returns (bool) {
        return balancerV1Reader.isBalancerV1Pool(pool, factory);
    }

    function batchERC4626ConvertToAssets(address[] calldata tokens) external view returns (ExtraPollingERC4626Response memory response) {
        return extraPollingReader.batchERC4626ConvertToAssets(tokens);
    }

    function batchRateProviderGetRate(address[] calldata rateProviders) external view returns (ExtraPollingRateProviderResponse memory response) {
        return extraPollingReader.batchRateProviderGetRate(rateProviders);
    }

    function batchChainlinkOracleData(address[] calldata oracles) external view returns (ExtraPollingChainlinkResponse memory response) {
        return extraPollingReader.batchChainlinkOracleData(oracles);
    }

    function batchOracleRate(OracleQuery[] calldata queries) external view returns (ExtraPollingOracleResponse memory result){
        return extraPollingReader.batchOracleRate(queries);
    }

    function batchRebasingBalances(RebasingQuery[] calldata queries) external view returns (ExtraPollingRebasingResponse memory result){
        return extraPollingReader.batchRebasingBalances(queries);
    }

    function erc4626PoolInfo(address vault, address handler) external view returns (Erc4626Response memory result){
        return erc4626Reader.erc4626PoolInfo(vault, handler);
    }


    function curveLlamaLendPoolInfo(address poolAddr, int256 maxBandWindow) external view returns (CurveLlamaLendResponse memory) {
        return curveLlamaLendReader.curveLlamaLendPoolInfo(poolAddr, maxBandWindow);
    }

    function curveLlamaLendFactoryAmms(address[] calldata factories) external view returns (address[] memory) {
        return curveLlamaLendReader.curveLlamaLendFactoryAmms(factories);
    }

    function batchLlamaOracleRate(address[] calldata pools) external view returns (ExtraPollingLlamaOracleResponse memory result){
        return extraPollingReader.batchLlamaOracleRate(pools);
    }

    function originArmPoolInfo(OriginArmRequest calldata params) external view returns (OriginArmResponse memory) {
        return originArmReader.originArmPoolInfo(params);
    }

    function obricV2PoolInfo(address poolAddr) external view returns (ObricV2Response memory) {
        return obricV2Reader.obricV2PoolInfo(poolAddr);
    }

    function dodoV1PoolInfo(address pool) external view returns (DoDoV1Response memory) {
        return dodoV1Reader.dodoV1PoolInfo(pool);
    }

    function dodoGspPoolInfo(address pool) external view returns (DoDoGspResponse memory) {
        return dodoGspReader.dodoGspPoolInfo(pool);
    }

    function ekuboPoolInfo(EkuboPoolInfoRequest calldata params) external view returns (EkuboPoolInfoResponse memory) {
        return ekuboReader.ekuboPoolInfo(params);
    }

    function ekuboPoolInfoV3(EkuboPoolInfoRequestV3 calldata params) external view returns (EkuboPoolInfoResponse memory) {
        return ekuboReader.ekuboPoolInfoV3(params);
    }

    function curveStableFactoryV2(CurveFactoryRequest calldata params) external view returns (CurveFilterResponseV2 memory ){
        return curveStableReader.curveStableFactoryV2(params);
    }

    function curveFactory(CurveFactoryRequest calldata params) external view returns (address){
        return curveStableReader.curveFactory(params);
    }
    function curveBaseInfo(CurveFactoryRequest calldata params) external view returns (CurveBaseInfoResponse memory response){
        return curveStableReader.curveBaseInfo(params);
    }

    function curveStablePoolInfoV3(CurveFactoryRequest calldata params) external view returns (CurveStableResponseV3 memory ){
        return curveStableReader.curveStablePoolInfoV3(params);
    }

    function curveCryptoPoolInfoV2(CurveFactoryRequest calldata params) external view returns (CurveCryptoResponseV2 memory ){
        return curveStableReader.curveCryptoPoolInfoV2(params);
    }
}
