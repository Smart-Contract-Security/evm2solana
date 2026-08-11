// SPDX-License-Identifier: MIT

/**
 * @title BasicRoyaltiesBase
 * @author Limit Break, Inc.
 * @dev Base functionality of an NFT mix-in contract implementing the most basic form of programmable royalties.
 */
abstract contract BasicRoyaltiesBase {

    event DefaultRoyaltySet(address receiver, uint64 feeNumerator);
    event TokenRoyaltySet(uint64 tokenId, address receiver, uint64 feeNumerator);

    function _setDefaultRoyalty(address receiver, uint64 feeNumerator) internal virtual {
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    function _setTokenRoyalty(uint64 tokenId, address receiver, uint64 feeNumerator) internal virtual {
        emit TokenRoyaltySet(tokenId, receiver, feeNumerator);
    }
}

/**
 * @title BasicRoyalties
 * @author Limit Break, Inc.
 * @notice Constructable BasicRoyalties Contract implementation.
 */
abstract contract BasicRoyalties is BasicRoyaltiesBase {
    constructor(address receiver, uint64 feeNumerator) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
}

/**
 * @title BasicRoyaltiesInitializable
 * @author Limit Break, Inc.
 * @notice Initializable BasicRoyalties Contract implementation to allow for EIP-1167 clones. 
 */
abstract contract BasicRoyaltiesInitializable is BasicRoyaltiesBase {}