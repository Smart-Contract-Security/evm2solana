// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../types/response.sol";
import {ExtraPollingERC4626Response, ExtraPollingRateProviderResponse, ExtraPollingChainlinkResponse, OracleQuery, ExtraPollingOracleResponse, RebasingQuery, ExtraPollingRebasingResponse, ExtraPollingLlamaOracleResponse} from "../types/response.sol";

interface IExtraPollingReader {
    function batchERC4626ConvertToAssets(address[] calldata tokens) external view returns (ExtraPollingERC4626Response memory result);
    function batchRateProviderGetRate(address[] calldata rateProviders) external view returns (ExtraPollingRateProviderResponse memory result);
    function batchChainlinkOracleData(address[] calldata oracles) external view returns (ExtraPollingChainlinkResponse memory result);
    function batchOracleRate(OracleQuery[] calldata queries) external view returns (ExtraPollingOracleResponse memory result);
    function batchRebasingBalances(RebasingQuery[] calldata queries) external view returns (ExtraPollingRebasingResponse memory result);
    function batchLlamaOracleRate(address[] calldata tokens) external view returns (ExtraPollingLlamaOracleResponse memory result);
}