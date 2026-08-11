// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IAssetRegistry {
    struct AssetConfig {
        address token;
        address vault;
        uint8 decimals;
        address oracle;
        bool listed;
        uint256 maxSwapNotional; // in input-token native decimals
        uint16 minCoverageBps;   // default 9000 (90%)
        uint16 depegDisableBps;  // default 50 (per-asset off-peg disable input)
        uint32 oracleHeartbeat;  // seconds
    }

    function getAsset(address token) external view returns (AssetConfig memory);
    function isPairEnabled(address a, address b) external view returns (bool);
    function isListed(address token) external view returns (bool);
    function vaultOf(address token) external view returns (address);

    event AssetAdded(address indexed asset, address indexed vault, address oracle);
    event PairEnabled(address indexed assetA, address indexed assetB);
    event PairDisabled(address indexed assetA, address indexed assetB);
    event AssetParamsUpdated(address indexed asset);
}
