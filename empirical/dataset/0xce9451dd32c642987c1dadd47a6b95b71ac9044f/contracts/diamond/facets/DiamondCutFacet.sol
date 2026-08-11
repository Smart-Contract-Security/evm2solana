// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IDiamondCut.sol";
import "../libraries/LibDiamond.sol";

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(FacetCut[] calldata diamondCut_, address init, bytes calldata calldata_) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(diamondCut_, init, calldata_);
    }
}
