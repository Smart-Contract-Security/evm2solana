// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "erc721a/contracts/ERC721A.sol";

import "./Renderer.sol";

/**
 * @title Onchainimals
 * @notice 4,444 fully onchain SVG pixel animals.
 *         All artwork composed on-chain at tokenURI() time from rect data
 *         stored in the Renderer contract. No IPFS, no off-chain dependencies.
 *
 *  - 4,444 max supply
 *  - 0.0005 ETH per mint (≈ $0.99)
 *  - 20 max per wallet
 *  - 5% royalty (ERC-2981, immutable)
 *  - Fully public mint, no allowlist, no owner reservations
 *  - Hard-coded distribution: 5 1/1s + 60 partyhats + 25 DDS + 25 Dragon Spears
 *    are guaranteed in the supply. RNG only decides WHO gets them via
 *    a one-time shuffle seed set at openMint().
 */
contract Onchainimals is ERC721A, ERC2981, Ownable {
    using Strings for uint256;

    // ============ CONSTANTS ============

    uint256 public constant MAX_SUPPLY = 4444;
    uint256 public constant MINT_PRICE = 0.0005 ether;
    uint256 public constant MAX_PER_WALLET = 20;
    uint96  public constant ROYALTY_BPS = 500; // 5.00%

    // Reserved trait positions (positions in the shuffled slot space)
    uint256 public constant ONE_OF_ONES = 5;        // slots 0-4
    uint256 public constant PARTYHAT_COUNT = 60;    // slots 5-64  (10 each x 6 colors)
    uint256 public constant DRAGON_DAGGER_COUNT = 25; // slots 65-89
    uint256 public constant DRAGON_SPEAR_COUNT = 25;  // slots 90-114
    uint256 public constant SPECIAL_SLOTS = 115;     // total special

    // ============ STATE ============

    bool    public mintOpen;
    uint256 public startingIndex;     // set once at openMint() — shuffles which tokenIds get special traits
    address public renderer;          // address of the Renderer contract

    mapping(address => uint256) public mintedBy;

    // ============ ERRORS ============

    error MintClosed();
    error MaxSupplyExceeded();
    error MaxPerWalletExceeded();
    error WrongValue();
    error ZeroAmount();
    error InvalidRenderer();
    error AlreadyOpen();

    // ============ EVENTS ============

    event MintOpened(uint256 startingIndex);
    event RendererUpdated(address renderer);

    // ============ CONSTRUCTOR ============

    /**
     * @param _royaltyReceiver wallet that receives 5% secondary royalties
     * @param _renderer address of the deployed Renderer contract
     */
    constructor(address _royaltyReceiver, address _renderer)
        ERC721A("Onchainimals", "ANIMALS")
        Ownable(msg.sender)
    {
        if (_renderer == address(0)) revert InvalidRenderer();
        _setDefaultRoyalty(_royaltyReceiver, ROYALTY_BPS);
        renderer = _renderer;
    }

    // ============ MINT ============

    function mint(uint256 quantity) external payable {
        if (!mintOpen) revert MintClosed();
        if (quantity == 0) revert ZeroAmount();
        if (_totalMinted() + quantity > MAX_SUPPLY) revert MaxSupplyExceeded();
        if (mintedBy[msg.sender] + quantity > MAX_PER_WALLET) revert MaxPerWalletExceeded();
        if (msg.value != quantity * MINT_PRICE) revert WrongValue();

        mintedBy[msg.sender] += quantity;
        _mint(msg.sender, quantity);
    }

    // ============ OWNER ============

    /**
     * @notice Opens mint AND fixes the shuffle seed. Single one-way switch.
     *         Once called, startingIndex is permanently set — no one can change which
     *         tokenIds correspond to which special items.
     */
    function openMint() external onlyOwner {
        if (mintOpen) revert AlreadyOpen();
        mintOpen = true;
        // Use prevrandao + block info for one-shot shuffle. Owner cannot
        // re-roll this — it's set once and immutable.
        startingIndex = uint256(
            keccak256(abi.encodePacked(block.prevrandao, block.timestamp, blockhash(block.number - 1)))
        ) % MAX_SUPPLY;
        emit MintOpened(startingIndex);
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    function setRenderer(address _renderer) external onlyOwner {
        if (_renderer == address(0)) revert InvalidRenderer();
        renderer = _renderer;
        emit RendererUpdated(_renderer);
    }

    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        _setDefaultRoyalty(receiver, bps);
    }

    // ============ VIEW ============

    /**
     * @notice Returns the shuffled slot for a tokenId.
     *         Slot determines which special trait (if any) this token gets.
     */
    function slotOf(uint256 tokenId) public view returns (uint256) {
        return (tokenId + startingIndex) % MAX_SUPPLY;
    }

    /**
     * @notice Returns the trait category for a slot.
     *  0 = standard (RNG-generated traits)
     *  1 = 1/1 (one of the 5 unique icons)
     *  2 = partyhat (one of 60 partyhats)
     *  3 = dragon dagger (one of 25)
     *  4 = dragon spear (one of 25)
     */
    function specialKindOf(uint256 slot) public pure returns (uint8) {
        if (slot < ONE_OF_ONES) return 1;
        if (slot < ONE_OF_ONES + PARTYHAT_COUNT) return 2;
        if (slot < ONE_OF_ONES + PARTYHAT_COUNT + DRAGON_DAGGER_COUNT) return 3;
        if (slot < SPECIAL_SLOTS) return 4;
        return 0;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        uint256 slot = slotOf(tokenId);
        uint8 kind = specialKindOf(slot);

        // Renderer composes the SVG + metadata JSON from slot info.
        return IRenderer(renderer).renderTokenURI(tokenId, slot, kind);
    }

    /**
     * @notice Collection-level metadata for OpenSea + other marketplaces.
     *         Used to autopopulate the collection page (name, description, external link).
     */
    function contractURI() external pure returns (string memory) {
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(
                '{"name":"Onchainimals",'
                '"description":"4,444 fully onchain pixel animals etched on Ethereum forever. 100% onchain SVG. No IPFS, no off-chain dependency. Hidden CT lore baked into the traits.",'
                '"external_link":"https://onchainimals.com"}'
            ))
        ));
    }

    // ============ INTERFACE ============

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}
