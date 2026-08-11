// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IAccessPredicate.sol";

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title NormiesSwarmPredicate
/// @notice ERC-8257 access predicate — grants access only to Normies NFT holders
/// @dev staticcall-safe (view only). Phase 2: additional collections can be added.
contract NormiesSwarmPredicate is IAccessPredicate {

    // Normies NFT — Ethereum Mainnet
    address public constant NORMIES_CONTRACT = 0x9Eb6E2025B64f340691e424b7fe7022fFDE12438;

    // Phase 2: additional approved collections (e.g. Bitfauna agents)
    mapping(address => bool) public approvedCollections;
    address[]                public approvedCollectionsList; // iterable for hasAccess
    address public owner;

    event CollectionAdded(address indexed collection);
    event CollectionRemoved(address indexed collection);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        // Normies is always approved
        approvedCollections[NORMIES_CONTRACT] = true;
    }

    /// @notice Returns true if the account holds at least 1 Normie (or approved collection NFT)
    /// @param account  Agent's Ethereum wallet
    /// @param data    Unused in Phase 1 (reserved for future tokenId-specific checks)
    function hasAccess(address account, bytes calldata data) external view override returns (bool) {
        // Primary: Normies
        if (IERC721(NORMIES_CONTRACT).balanceOf(account) > 0) {
            return true;
        }
        // Phase 2+: additional approved collections (e.g. Bitfauna)
        for (uint256 i = 0; i < approvedCollectionsList.length; i++) {
            if (IERC721(approvedCollectionsList[i]).balanceOf(account) > 0) {
                return true;
            }
        }
        return false;
    }

    /// @notice Add a future NFT collection as approved predicate
    function addCollection(address collection) external onlyOwner {
        require(!approvedCollections[collection], "Already approved");
        approvedCollections[collection] = true;
        approvedCollectionsList.push(collection);
        emit CollectionAdded(collection);
    }

    /// @notice Remove a collection from approved list
    function removeCollection(address collection) external onlyOwner {
        require(collection != NORMIES_CONTRACT, "Cannot remove Normies");
        approvedCollections[collection] = false;
        // Remove from list (swap-and-pop)
        for (uint256 i = 0; i < approvedCollectionsList.length; i++) {
            if (approvedCollectionsList[i] == collection) {
                approvedCollectionsList[i] = approvedCollectionsList[approvedCollectionsList.length - 1];
                approvedCollectionsList.pop();
                break;
            }
        }
        emit CollectionRemoved(collection);
    }
}
