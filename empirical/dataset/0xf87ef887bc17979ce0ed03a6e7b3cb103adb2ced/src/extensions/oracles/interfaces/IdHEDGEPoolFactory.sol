// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IdHEDGEPoolFactory {
    function isPool(address pool) external view returns (bool);

    /// @notice Address of the dhedge `AssetHandler`. Captured at
    ///         `SimpleOracleModule` deploy time and stored as an immutable.
    function getAssetHandler() external view returns (address);
}
