// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Dmn data structure.
struct DmnSeedData {
    /// @dev Dmn ID.
    uint256 id;
    /// @dev Dmn seed.
    uint256 seed;
}

/// @dev Dmn collection interface.
/// Each owner has a list of Dmns with unique IDs and seed values.
interface IDmn {
    /// @dev Error when the caller doesn't own the Dmn.
    error NotDmnOwner();
    /// @dev Error when Dmn index is out of range.
    error DmnIndexOutOfRange();

    /// @dev Dmn mint event.
    event OnDmnMinted(address indexed owner, uint256 dmnId);
    /// @dev Compact range mint event for large swap outputs.
    event OnDmnRangeMinted(address indexed owner, uint256 startDmnId, uint256 endDmnId);
    /// @dev Dmn burn event.
    event OnDmnBurned(address indexed owner, uint256 dmnId);
    /// @dev Dmn transfer event.
    event OnDmnTransfer(address indexed from, address indexed to, uint256 dmnId);

    /// @dev Total Dmn count.
    function DmnsTotalCount() external view returns (uint256);
    /// @dev Total holder count.
    function HoldersCount() external view returns (uint256);
    /// @dev Dmn count for an owner.
    function OwnerDmnsCount(address owner) external view returns (uint256);
    /// @dev Returns a paginated list of Dmns.
    /// @param owner Owner address
    /// @param page Page number
    /// @param pageSize Page size
    function OwnerDmnsPage(address owner, uint256 page, uint256 pageSize)
        external
        view
        returns (DmnSeedData[] memory dmns);
    /// @dev Dmn for an owner by index.
    /// @param owner Owner address
    /// @param index Dmn index
    function OwnerDmn(address owner, uint256 index) external view returns (DmnSeedData memory);
    /// @dev Dmn index for an owner by ID.
    /// @param owner Owner address
    /// @param dmnId Dmn ID
    function OwnerDmnIndex(address owner, uint256 dmnId) external view returns (uint256 index);
    /// @dev Reorders a Dmn for an owner. Shifts all items left/right (may be gas-inefficient).
    /// @param owner Owner address
    /// @param dmnId Dmn ID to reorder
    /// @param newIndex New index
    function ReorderDmn(address owner, uint256 dmnId, uint256 newIndex) external;
    /// @dev Reorders a Dmn for an owner. Gas-optimized swap without shifting.
    /// @param owner Owner address
    /// @param dmnId Dmn ID to reorder
    /// @param newIndex New index or swap index
    function ReorderDmnPair(address owner, uint256 dmnId, uint256 newIndex) external;
    /// @dev Checks if the owner owns a Dmn by ID.
    function OwnerOwns(address owner, uint256 dmnId) external view returns (bool);
    /// @dev Checks if the owner is a holder.
    function IsHolder(address owner) external view returns (bool);
    /// @dev Holder by index.
    function Holder(uint256 index) external view returns (address);
    /// @dev Holder number by address.
    function HolderNumber(address owner) external view returns (uint256);

    /// @dev Transfers a Dmn to an address. One token is transferred with the Dmn.
    /// @param to Recipient address
    /// @param dmnId Dmn ID
    function transferDmn(address to, uint256 dmnId) external;
    /// @dev Transfers multiple Dmns. Transfers the same number of tokens.
    /// @param to Recipient address
    /// @param dmnIds Array of Dmn IDs
    function transferDmnsList(address to, uint256[] calldata dmnIds) external;
}
