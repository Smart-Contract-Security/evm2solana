// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/**
 * @title DiamondDronesFilm
 * @notice 1/1 film NFT contract for the DIAMOND DRONES ARE A GIRL'S BEST FRIEND
 *         film series by Miss AL Simpson.
 *
 *         Each film is deployed as its own contract with a single token (Token #1).
 *         The film video is stored on IPFS as the animation_url in metadata.
 *         Full 4K master available via token-gated download on diamonddrones.world.
 *
 * =====================================================================
 *  NFT OWNERSHIP & LICENSE TERMS (on-chain)
 * =====================================================================
 *
 *  1. EDITION: This is a unique 1/1 film artwork. Only one token exists
 *     on this contract.
 *
 *  2. PERSONAL LICENSE: The holder is granted a worldwide, non-exclusive,
 *     royalty-free license to display and screen the film for personal,
 *     non-commercial purposes.
 *
 *  3. INTELLECTUAL PROPERTY: The Artist (Miss AL Simpson / Miss AL Simpson
 *     Limited) retains all intellectual property rights including but not
 *     limited to copyright, reproduction rights, commercial exploitation
 *     rights, soundtrack rights, and derivative work rights. DIAMOND DRONES
 *     is a registered trademark of Miss AL Simpson Limited.
 *
 *  4. SOUNDTRACK: All musical compositions and sound recordings contained
 *     within the film remain the exclusive property of the Artist. No
 *     rights to the soundtrack are transferred with this NFT.
 *
 *  5. RECALL: The Artist reserves the right to recall this NFT at any time
 *     for IP vaulting purposes. In the event of recall, the Artist will
 *     transfer fair market value to the holder at the time of recall.
 *
 *  6. COLLECTOR BENEFIT: The holder may access the full 4K archival master
 *     via token-gated download at diamonddrones.world.
 * =====================================================================
 */
contract DiamondDronesFilm is ERC721A, Ownable, ERC2981 {

    uint256 public constant MAX_SUPPLY = 1;

    string private _baseTokenURI;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint96 royaltyBps_
    ) ERC721A(name_, symbol_) Ownable(msg.sender) {
        _baseTokenURI = baseURI_;
        _setDefaultRoyalty(msg.sender, royaltyBps_);
    }

    // ── Token ID starts at 1 ──────────────────────────────
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ── Mint ──────────────────────────────────────────────
    function ownerMint() external onlyOwner {
        require(totalSupply() < MAX_SUPPLY, "Already minted");
        _mint(msg.sender, 1);
    }

    // ── Metadata ──────────────────────────────────────────
    // 1/1 contract: tokenURI returns the stored URI directly (no tokenId suffix)
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        return _baseTokenURI;
    }

    function setBaseURI(string calldata newURI) external onlyOwner {
        _baseTokenURI = newURI;
    }

    // ── Artist Recall (IP vaulting) ───────────────────────
    function recall(uint256 tokenId) external onlyOwner {
        address holder = ownerOf(tokenId);
        transferFrom(holder, msg.sender, tokenId);
    }

    // ── ERC-165 ───────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721A, ERC2981)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId)
            || ERC2981.supportsInterface(interfaceId);
    }

    // ── License (on-chain readable) ───────────────────────
    function licenseTerms() external pure returns (string memory) {
        return
            "1/1 FILM LICENSE: "
            "(1) EDITION - Unique 1/1 film artwork, single token. "
            "(2) PERSONAL LICENSE - Holder granted worldwide, non-exclusive, "
            "royalty-free license for personal, non-commercial display and screening. "
            "(3) INTELLECTUAL PROPERTY - Artist retains all IP rights including "
            "copyright, reproduction, commercial exploitation, soundtrack rights, "
            "and derivative works. DIAMOND DRONES is a registered trademark. "
            "(4) SOUNDTRACK - All music and sound recordings remain exclusive "
            "property of the Artist. No soundtrack rights transferred. "
            "(5) RECALL - Artist may recall for IP vaulting at fair market value. "
            "(6) COLLECTOR BENEFIT - 4K archival master via token-gated download.";
    }
}
