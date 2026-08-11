// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IDiamondLoupe.sol";
import "../libraries/LibDiamond.sol";

contract DiamondLoupeFacet is IDiamondLoupe {
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 length = ds.facetAddresses.length;
        facets_ = new Facet[](length);
        for (uint256 i = 0; i < length; i++) {
            address facet = ds.facetAddresses[i];
            facets_[i] = Facet(facet, ds.facetFunctionSelectors[facet].selectors);
        }
    }

    function facetFunctionSelectors(address facet) external view override returns (bytes4[] memory selectors) {
        selectors = LibDiamond.diamondStorage().facetFunctionSelectors[facet].selectors;
    }

    function facetAddresses() external view override returns (address[] memory facetAddresses_) {
        facetAddresses_ = LibDiamond.diamondStorage().facetAddresses;
    }

    function facetAddress(bytes4 selector) external view override returns (address facetAddress_) {
        facetAddress_ = LibDiamond.diamondStorage().selectorToFacetAndPosition[selector].facetAddress;
    }
}