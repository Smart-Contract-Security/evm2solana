// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IArtvybeCollection.sol";

/// @title IArtvybeCollectionV2
/// @notice V2 extends V1 with owner-controlled, raise-only supply expansion and an
///         optional one-way lock so creators can freeze the cap when their collection
///         is final. V1 deployed `maxSupply` as `immutable` and therefore cannot be
///         retrofitted; this interface only applies to collections deployed by the V2 factory.
interface IArtvybeCollectionV2 is IArtvybeCollection {
    event MaxSupplyExtended(uint256 oldCap, uint256 newCap);
    event SupplyLocked(uint256 finalCap);

    /// @notice Increase `maxSupply` by `additional`. Reverts if supply is locked or `additional == 0`.
    function extendMaxSupply(uint256 additional) external;

    /// @notice One-way lock — once called, `extendMaxSupply` will revert forever.
    function lockSupply() external;

    /// @notice Whether the supply has been permanently locked.
    function supplyLocked() external view returns (bool);

    /// @notice Returns "v2" so the frontend can branch without selector probing.
    function version() external pure returns (string memory);
}
