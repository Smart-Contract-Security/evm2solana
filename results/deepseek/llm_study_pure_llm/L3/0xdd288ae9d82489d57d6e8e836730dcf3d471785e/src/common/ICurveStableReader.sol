Given the complexity of porting this Solidity interface to Solana using Solang, I need to make several adjustments. Solang for Solana doesn't support custom struct imports in the same way, and the memory/calldata patterns differ. Here's the ported version:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Define structs inline since imports may not work the same way in Solang
struct CurveFactoryRequest {
    address pool;
    // Add other fields as needed based on the original struct
}

struct CurveBaseInfoResponse {
    bool isCurve;
    address factory;
    // Add other fields as needed
}

struct CurveFilterResponseV2 {
    bool isValid;
    address factory;
    // Add other fields as needed
}

struct CurveStableResponseV3 {
    uint256 totalSupply;
    uint256[] balances;
    // Add other fields as needed
}

struct CurveCryptoResponseV2 {
    uint256 totalSupply;
    uint256[] balances;
    // Add other fields as needed
}

interface ICurveStableReader {
    function curveBaseInfo(CurveFactoryRequest calldata params) external view returns (CurveBaseInfoResponse memory response);
    
    // Check if pool belongs to Curve protocol and return corresponding factory address
    function curveFactory(CurveFactoryRequest calldata params) external view returns (address);
    
    // Curve stable requires multiple filter conditions, returns factory and other conditions
    function curveStableFactoryV2(CurveFactoryRequest calldata params) external view returns (CurveFilterResponseV2 memory response);
    
    // Stable coin pool information
    function curveStablePoolInfoV3(CurveFactoryRequest calldata params) external view returns (CurveStableResponseV3 memory response);
    
    // Non-stable coin pool information
    function curveCryptoPoolInfoV2(CurveFactoryRequest calldata params) external view returns (CurveCryptoResponseV2 memory response);
}
```

Note: The struct definitions are placeholders. You'll need to fill in the actual fields based on the original `request.sol` and `response.sol` files. Solang for Solana supports `calldata` and `memory` keywords, but the struct definitions must be available in the same file or properly imported according to Solang's import system.