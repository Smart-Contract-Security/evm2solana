// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @title BasicRoyaltiesBase
 * @author Limit Break, Inc.
 * @dev Base functionality of an NFT mix-in contract implementing the most basic form of programmable royalties.
 */
abstract contract BasicRoyaltiesBase {

    event DefaultRoyaltySet(address indexed receiver, uint96 feeNumerator);
    event TokenRoyaltySet(uint256 indexed tokenId, address indexed receiver, uint96 feeNumerator);

    function _setDefaultRoyalty(address receiver, uint96 feeNumerator) internal virtual {
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    function _setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) internal virtual {
        emit TokenRoyaltySet(tokenId, receiver, feeNumerator);
    }
}

/**
 * @title BasicRoyalties
 * @author Limit Break, Inc.
 * @notice Constructable BasicRoyalties Contract implementation.
 */
abstract contract BasicRoyalties is BasicRoyaltiesBase {
    constructor(address receiver, uint96 feeNumerator) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
}

/**
 * @title BasicRoyaltiesInitializable
 * @author Limit Break, Inc.
 * @notice Initializable BasicRoyalties Contract implementation to allow for EIP-1167 clones. 
 */
abstract contract BasicRoyaltiesInitializable is BasicRoyaltiesBase {}