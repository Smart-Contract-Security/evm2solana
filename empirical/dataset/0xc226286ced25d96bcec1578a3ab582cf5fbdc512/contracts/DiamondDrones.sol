// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/**
 * @title DiamondDrones
 * @notice DIAMOND DRONES(TM) Genesis Collection — 1000 unique Diamond Drones
 *         by Miss AL Simpson.
 *
 *         Uses ERC721A for gas-efficient batch minting. All 1000 tokens can
 *         be minted to the artist wallet in a single transaction.
 *
 * ═══════════════════════════════════════════════════════════════════════
 *  NFT OWNERSHIP & LICENSE TERMS (on-chain)
 * ═══════════════════════════════════════════════════════════════════════
 *
 *  1. OWNERSHIP: The holder of each NFT token owns that specific NFT and
 *     the unique digital artwork associated with it. Ownership of both the
 *     NFT and the artwork transfers automatically with the token upon sale
 *     or transfer.
 *
 *  2. DISPLAY RIGHTS: The NFT holder may display, exhibit, and enjoy the
 *     artwork for personal and non-commercial purposes, including in
 *     virtual galleries, social media profiles, and personal collections.
 *
 *  3. RESALE RIGHTS: The NFT holder may freely sell, trade, or transfer
 *     their NFT on any marketplace. All ownership and display rights
 *     transfer to the new holder upon transfer of the token.
 *
 *  4. TRADEMARK: The name "DIAMOND DRONES" is a registered trademark
 *     owned by MISS AL SIMPSON LIMITED. No transfer of trademark rights
 *     is granted to NFT holders. The holder may not use the DIAMOND DRONES
 *     name, brand, or logo for any commercial purpose without prior written
 *     consent from MISS AL SIMPSON LIMITED.
 *
 *  5. RESTRICTIONS: The NFT holder may NOT use the DIAMOND DRONES trademark,
 *     brand identity, or associated IP of MISS AL SIMPSON LIMITED for
 *     commercial purposes, merchandising, or sub-licensing without prior
 *     written consent.
 *
 *  6. RECALL: This contract includes an artist recall mechanism. The Artist
 *     reserves the right to recall tokens for IP vaulting purposes.
 * ═══════════════════════════════════════════════════════════════════════
 */
contract DiamondDrones is ERC721A, ERC2981, Ownable, Pausable, ReentrancyGuard {

    uint256 public constant MAX_SUPPLY = 1000;

    string private _baseTokenURI;

    event AllTokensRecalled(uint256 totalRecalled, uint256 timestamp);
    event BatchRecalled(uint256 startTokenId, uint256 count, uint256 timestamp);

    constructor(
        string memory baseURI_,
        uint96 royaltyBps_
    ) ERC721A("Diamond Drones", "DRONE") Ownable(msg.sender) {
        _baseTokenURI = baseURI_;
        _setDefaultRoyalty(msg.sender, royaltyBps_);
    }

    // ═══════════════════════════════════════════════════
    //  OWNER MINT (batch — all 1000 in one tx)
    // ═══════════════════════════════════════════════════

    /**
     * @notice Mint `quantity` tokens to the owner wallet.
     *         ERC721A makes this O(1) regardless of quantity.
     */
    function ownerMint(uint256 quantity) external onlyOwner {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        _mint(owner(), quantity);
    }

    // ═══════════════════════════════════════════════════
    //  RECALL (IP vaulting)
    // ═══════════════════════════════════════════════════

    /**
     * @notice Recall all tokens not already held by the owner.
     *         Must be paused first.
     */
    function recallAll() external onlyOwner whenPaused nonReentrant {
        uint256 total = _totalMinted();
        require(total > 0, "No tokens to recall");

        uint256 recalled = 0;
        for (uint256 tokenId = 0; tokenId < total; tokenId++) {
            if (_exists(tokenId)) {
                address tokenOwner = ownerOf(tokenId);
                if (tokenOwner != owner()) {
                    _recallToken(tokenOwner, owner(), tokenId);
                    recalled++;
                }
            }
        }

        emit AllTokensRecalled(recalled, block.timestamp);
    }

    /**
     * @notice Recall tokens in batches for gas efficiency.
     */
    function recallBatch(uint256 startTokenId, uint256 count) external onlyOwner whenPaused nonReentrant {
        uint256 total = _totalMinted();
        uint256 endTokenId = startTokenId + count;
        if (endTokenId > total) endTokenId = total;

        uint256 recalled = 0;
        for (uint256 tokenId = startTokenId; tokenId < endTokenId; tokenId++) {
            if (_exists(tokenId)) {
                address tokenOwner = ownerOf(tokenId);
                if (tokenOwner != owner()) {
                    _recallToken(tokenOwner, owner(), tokenId);
                    recalled++;
                }
            }
        }

        emit BatchRecalled(startTokenId, recalled, block.timestamp);
    }

    /**
     * @dev Approve this contract to move the token, then transfer.
     *      Only callable within onlyOwner + whenPaused recall functions.
     */
    function _recallToken(address from, address to, uint256 tokenId) internal {
        _approve(to, tokenId);
        transferFrom(from, to, tokenId);
    }

    // ═══════════════════════════════════════════════════
    //  OWNER SETTERS
    // ═══════════════════════════════════════════════════

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ═══════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Returns the NFT ownership and license terms.
     */
    function licenseTerms() external pure returns (string memory) {
        return
            "DIAMOND DRONES - NFT OWNERSHIP & LICENSE TERMS: "
            "(1) OWNERSHIP - The holder of each NFT owns that NFT and the unique digital artwork. "
            "Ownership of both the NFT and the artwork transfers automatically with the token. "
            "(2) DISPLAY RIGHTS - The holder may display, exhibit, and enjoy the artwork "
            "for personal and non-commercial purposes. "
            "(3) RESALE - The holder may freely sell, trade, or transfer. "
            "All ownership and display rights transfer with the token. "
            "(4) TRADEMARK - The name DIAMOND DRONES is a registered trademark owned by "
            "MISS AL SIMPSON LIMITED. No transfer of trademark rights is granted to NFT holders. "
            "The holder may not use the DIAMOND DRONES name, brand, or logo for any commercial "
            "purpose without prior written consent from MISS AL SIMPSON LIMITED. "
            "(5) RESTRICTIONS - The holder may NOT use the DIAMOND DRONES trademark, brand identity, "
            "or associated IP of MISS AL SIMPSON LIMITED for commercial purposes, merchandising, "
            "or sub-licensing without prior written consent. "
            "(6) RECALL - This contract includes an artist recall mechanism for IP vaulting.";
    }

    // ═══════════════════════════════════════════════════
    //  OVERRIDES
    // ═══════════════════════════════════════════════════

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721A, ERC2981) returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    /**
     * @notice Token IDs start at 0 (Diamond Drone #0000 through #0999).
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 0;
    }
}
