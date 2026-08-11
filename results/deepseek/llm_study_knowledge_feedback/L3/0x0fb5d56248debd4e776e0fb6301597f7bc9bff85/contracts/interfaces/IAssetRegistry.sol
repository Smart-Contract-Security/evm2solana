import 'solana';

interface IAssetRegistry {
    struct AssetConfig {
        address token;
        address vault;
        uint8 decimals;
        address oracle;
        bool listed;
        uint64 maxSwapNotional;
        uint16 minCoverageBps;
        uint16 depegDisableBps;
        uint32 oracleHeartbeat;
    }

    function getAsset(address token) external view returns (AssetConfig memory);
    function isPairEnabled(address a, address b) external view returns (bool);
    function isListed(address token) external view returns (bool);
    function vaultOf(address token) external view returns (address);

    event AssetAdded(address asset, address vault, address oracle);
    event PairEnabled(address assetA, address assetB);
    event PairDisabled(address assetA, address assetB);
    event AssetParamsUpdated(address asset);
}