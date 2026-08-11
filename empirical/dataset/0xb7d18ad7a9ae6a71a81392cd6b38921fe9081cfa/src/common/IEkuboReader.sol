// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {EkuboPoolInfoRequest,EkuboPoolInfoRequestV3} from "../types/request.sol";
import {EkuboPoolInfoResponse} from "../types/response.sol";

interface IEkuboReader {
    /// @notice Read Ekubo V2 pool information including state, tokens, and ticks
    /// @param params Request parameters containing pool manager, pool ID, pool key, and bitmap limits
    /// @return response Full pool information
    function ekuboPoolInfo(EkuboPoolInfoRequest calldata params) external view returns (EkuboPoolInfoResponse memory response);
    
    /// @notice Read Ekubo V3 pool information including state, tokens, ticks, and pool type
    /// @param params Request parameters containing Core contract address, pool ID, pool key (with PoolConfig), and bitmap limits
    /// @return response Full pool information with V3-specific fields (poolType, amplification, centerTick)
    /// @dev V3 uses Singleton architecture with Core contract and packed PoolConfig (bytes32)
    /// @dev Supports three pool types: Concentrated, Stableswap, and Full Range
    function ekuboPoolInfoV3(EkuboPoolInfoRequestV3 calldata params) external view returns (EkuboPoolInfoResponse memory response);
}

