// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TraitCategory, TraitVariant} from "../OCCV2TraitTypes.sol";

/// @title IOCCV2TraitRegistry — Interface for the on-chain trait data store
interface IOCCV2TraitRegistry {
    /// @notice Emitted when a batch of trait variants is added to a category
    event TraitBatchAdded(TraitCategory indexed category, uint256 count);

    function getTraitSVG(TraitCategory category, uint256 variantIndex)
        external
        view
        returns (string memory);

    function getTraitVariant(TraitCategory category, uint256 variantIndex)
        external
        view
        returns (TraitVariant memory);

    function getTraitCount(TraitCategory category) external view returns (uint256);

    /// @notice Bit-packed selection data for every variant in `category`, in
    ///         index order. One `uint256` per variant (see the `TraitSelection`
    ///         library for the layout). Lets the trait seeder fetch a whole
    ///         category's pick-relevant data in a single call — the gas-optimized
    ///         read path for the weighted variant selection.
    function getSelectionData(TraitCategory category)
        external
        view
        returns (uint256[] memory);
}
