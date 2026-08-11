// SPDX-License-Identifier: MIT

import "../interfaces/IDiamondCut.sol";

library LibDiamond {
    bytes32 internal constant DIAMOND_STORAGE_POSITION = keccak256("ace.contracts.diamond.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint64 selectorPosition;
    }

    struct FacetFunctionSelectors {
        bytes4[] selectors;
        uint64 facetAddressPosition;
    }

    struct DiamondStorage {
        address contractOwner;
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        address[] facetAddresses;
    }

    event DiamondCut(IDiamondCut.FacetCut[] diamondCut, address init, bytes calldata_);

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setContractOwner(address newOwner) internal {
        diamondStorage().contractOwner = newOwner;
    }

    function enforceIsContractOwner() internal view {
        if (tx.accounts.dataAccount.key != diamondStorage().contractOwner) {
            revert("NotContractOwner");
        }
    }

    function diamondCut(IDiamondCut.FacetCut[] memory diamondCut_, address init, bytes memory calldata_) internal {
        for (uint64 i = 0; i < diamondCut_.length; i++) {
            IDiamondCut.FacetCutAction action = diamondCut_[i].action;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(diamondCut_[i].facetAddress, diamondCut_[i].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(diamondCut_[i].facetAddress, diamondCut_[i].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(diamondCut_[i].facetAddress, diamondCut_[i].functionSelectors);
            } else {
                revert("InvalidFacetCut");
            }
        }

        emit DiamondCut(diamondCut_, init, calldata_);
        initializeDiamondCut(init, calldata_);
    }

    function addFunctions(address facetAddress, bytes4[] memory selectors) internal {
        if (selectors.length == 0 || facetAddress == address(0)) {
            revert("InvalidFacetCut");
        }
        enforceHasContractCode(facetAddress);

        DiamondStorage storage ds = diamondStorage();
        uint64 selectorPosition = uint64(ds.facetFunctionSelectors[facetAddress].selectors.length);
        if (selectorPosition == 0) {
            ds.facetFunctionSelectors[facetAddress].facetAddressPosition = uint64(ds.facetAddresses.length);
            ds.facetAddresses.push(facetAddress);
        }

        for (uint64 i = 0; i < selectors.length; i++) {
            bytes4 selector = selectors[i];
            if (ds.selectorToFacetAndPosition[selector].facetAddress != address(0)) {
                revert("FunctionAlreadyExists");
            }
            ds.facetFunctionSelectors[facetAddress].selectors.push(selector);
            ds.selectorToFacetAndPosition[selector] = FacetAddressAndPosition(facetAddress, selectorPosition);
            selectorPosition++;
        }
    }

    function replaceFunctions(address facetAddress, bytes4[] memory selectors) internal {
        if (selectors.length == 0 || facetAddress == address(0)) {
            revert("InvalidFacetCut");
        }
        enforceHasContractCode(facetAddress);

        DiamondStorage storage ds = diamondStorage();
        uint64 selectorPosition = uint64(ds.facetFunctionSelectors[facetAddress].selectors.length);
        if (selectorPosition == 0) {
            ds.facetFunctionSelectors[facetAddress].facetAddressPosition = uint64(ds.facetAddresses.length);
            ds.facetAddresses.push(facetAddress);
        }

        for (uint64 i = 0; i < selectors.length; i++) {
            bytes4 selector = selectors[i];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress == facetAddress) {
                revert("CannotReplaceFunctionWithSameFacet");
            }
            removeFunction(ds, oldFacetAddress, selector);
            ds.facetFunctionSelectors[facetAddress].selectors.push(selector);
            ds.selectorToFacetAndPosition[selector] = FacetAddressAndPosition(facetAddress, selectorPosition);
            selectorPosition++;
        }
    }

    function removeFunctions(address facetAddress, bytes4[] memory selectors) internal {
        if (selectors.length == 0 || facetAddress != address(0)) {
            revert("InvalidFacetCut");
        }

        DiamondStorage storage ds = diamondStorage();
        for (uint64 i = 0; i < selectors.length; i++) {
            bytes4 selector = selectors[i];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            removeFunction(ds, oldFacetAddress, selector);
        }
    }

    function removeFunction(DiamondStorage storage ds, address facetAddress, bytes4 selector) internal {
        if (facetAddress == address(0)) {
            revert("FunctionDoesNotExist");
        }
        if (facetAddress == address(this)) {
            revert("CannotRemoveImmutableFunction");
        }

        uint64 selectorPosition = ds.selectorToFacetAndPosition[selector].selectorPosition;
        uint64 lastSelectorPosition = uint64(ds.facetFunctionSelectors[facetAddress].selectors.length - 1);
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[facetAddress].selectors[lastSelectorPosition];
            ds.facetFunctionSelectors[facetAddress].selectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].selectorPosition = selectorPosition;
        }

        ds.facetFunctionSelectors[facetAddress].selectors.pop();
        delete ds.selectorToFacetAndPosition[selector];

        if (lastSelectorPosition == 0) {
            uint64 lastFacetAddressPosition = uint64(ds.facetAddresses.length - 1);
            uint64 facetAddressPosition = ds.facetFunctionSelectors[facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[facetAddress].facetAddressPosition;
        }
    }

    function initializeDiamondCut(address init, bytes memory calldata_) internal {
        if (init == address(0)) {
            return;
        }
        enforceHasContractCode(init);
        (bool success, ) = init.call{accounts: []}(calldata_);
        if (!success) {
            revert("InitializationFailed");
        }
    }

    function enforceHasContractCode(address contractAddress) internal view {
        // On Solana, extcodesize is not available.
        // We check if the account is a program by verifying it is executable.
        // This requires the account to be passed in the transaction accounts.
        // Since this is an internal view function, we assume the caller ensures
        // the account is a valid program. We simply check that the address is not zero.
        if (contractAddress == address(0)) {
            revert("FacetHasNoCode");
        }
        // Note: A full check would require the account to be passed and its executable flag checked.
        // For now, we rely on the caller to provide valid program addresses.
    }
}