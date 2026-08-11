// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IPendlePT {
    function SY() external view returns (address);
    function YT() external view returns (address);
    function expiry() external view returns (uint256);
    function isExpired() external view returns (bool);
}

interface IPendleYT {
    function SY() external view returns (address);
    function PT() external view returns (address);
    function expiry() external view returns (uint256);
    function isExpired() external view returns (bool);
}

interface IPendleSY {
    function exchangeRate() external view returns (uint256);
    function assetInfo() external view returns (uint8 assetType, address assetAddress, uint8 assetDecimals);
    function yieldToken() external view returns (address);
}

interface IPendlePtOracle {
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256);
    function getYtToAssetRate(address market, uint32 duration) external view returns (uint256);
    function getOracleState(address market, uint32 duration)
        external
        view
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied);
}

interface IPendleAdapter {
    enum Mode {
        PT,
        YT
    }

    event ConfigSet(address indexed token, address market, address oracle, uint32 twapDuration);
    event ConfigRemoved(address indexed token);
}
