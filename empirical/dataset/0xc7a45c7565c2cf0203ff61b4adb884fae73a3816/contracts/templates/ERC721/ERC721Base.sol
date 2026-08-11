// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ChainForge — ERC721 Base (OZ v5 Compatible)
 *
 * Responsibilities:
 * - Establishes admin authority via AccessControl
 * - Provides deterministic supportsInterface override bridge
 * - Stores ChainForge NFT metadata base URI and URI suffix
 * - Adds ERC2981 royalty support
 *
 * Metadata behavior:
 * - baseURI_ = "ipfs://CID/"
 * - uriSuffix_ = ".json"
 * - tokenURI(1) = "ipfs://CID/1.json"
 *
 * Design:
 * - Does NOT include optional features (burn/pause/mint)
 * - Used as a shared base for generated ERC721 variants
 */

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

abstract contract ERC721Base is ERC721, AccessControl, ERC2981 {
    using Strings for uint256;

    string private _chainforgeBaseURI;
    string private _chainforgeUriSuffix;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory uriSuffix_,
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_
    )
        ERC721(name_, symbol_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _chainforgeBaseURI = baseURI_;
        _chainforgeUriSuffix = uriSuffix_;

        if (royaltyReceiver_ != address(0) && royaltyFeeNumerator_ > 0) {
            _setDefaultRoyalty(royaltyReceiver_, royaltyFeeNumerator_);
        }
    }

    function _baseURI()
        internal
        view
        virtual
        override
        returns (string memory)
    {
        return _chainforgeBaseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        _requireOwned(tokenId);

        string memory base = _baseURI();

        return bytes(base).length > 0
            ? string.concat(base, tokenId.toString(), _chainforgeUriSuffix)
            : "";
    }

    function chainforgeBaseURI()
        external
        view
        returns (string memory)
    {
        return _chainforgeBaseURI;
    }

    function chainforgeUriSuffix()
        external
        view
        returns (string memory)
    {
        return _chainforgeUriSuffix;
    }

    /**
     * OZ v5: ERC721, AccessControl, and ERC2981 implement supportsInterface.
     * Any contract inheriting all three must override and unify resolution.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}