// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";
import {ERC2981} from "solady/tokens/ERC2981.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title Posts — 222 fully on-chain SVG NFTs, minter-paid storage
/// @notice Tier 2 fully-on-chain: SVG bytes (minter-paid), plus poems and
///         traits and Inter font (owner pre-committed and SSTORE2'd).
contract Posts is ERC721, ERC2981, Ownable, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 222;
    uint256 public constant MINT_FEE = 0.01111 ether;

    /// Max royalty BPS the owner can ever set (10% — protects holders from a
    /// compromised owner cranking secondary-sale royalties to 100%).
    uint96 public constant MAX_ROYALTY_BPS = 1000;

    /// keccak256 of each token's final SVG bytes, committed at deploy.
    /// Index i ↔ tokenId (i + 1).
    bytes32[MAX_SUPPLY] public svgHashes;

    /// keccak256 of the packed poems / traits / font blobs, committed at deploy.
    bytes32 public immutable poemsHash;
    bytes32 public immutable traitsHash;
    bytes32 public immutable fontRegHash;
    bytes32 public immutable fontItaHash;

    /// SSTORE2 pointer to each token's raw SVG bytes (set on mint).
    /// 1-indexed; slot 0 unused.
    address[MAX_SUPPLY + 1] internal artPointer;

    /// SSTORE2 pointers to the packed metadata blobs (set by owner once).
    address public poemsPointer;
    address public traitsPointer;
    address public fontRegPointer;
    address public fontItaPointer;

    /// Mint fee is split 50/50 between primaryA and primaryB on every mint.
    /// Both addresses are mutable post-deploy via setTreasury so a frozen /
    /// compromised receiver can be rotated without bricking the collection.
    address public primaryA;
    address public primaryB;

    /// Public mint switch. Owner flips this to true to open mint. Default
    /// false so a fresh deploy is paused until the launch moment.
    bool public mintOpen;

    uint256 public totalMinted;

    event Minted(uint256 indexed tokenId, address indexed minter, address pointer);
    event MetadataSet(
        address poemsPointer,
        address traitsPointer,
        address fontRegPointer,
        address fontItaPointer
    );
    event TreasuryChanged(address indexed primaryA, address indexed primaryB);
    event MintOpenSet(bool open);

    error SoldOut();
    error WrongFee();
    error BadSvg();
    error PrimaryTransferFailed();
    error NotMinted();
    error MetadataAlreadySet();
    error MetadataNotSet();
    error BadMetadataHash();
    error InvalidTokenId();
    error ZeroAddress();
    error ZeroHash();
    error RoyaltyTooHigh();
    error UseHandover();
    error MintPaused();

    struct DeployArgs {
        bytes32 poemsHash;
        bytes32 traitsHash;
        bytes32 fontRegHash;
        bytes32 fontItaHash;
        address primaryA;
        address primaryB;
        address royaltyReceiver;
        uint96 royaltyBps;
        address owner;
    }

    constructor(bytes32[MAX_SUPPLY] memory hashes, DeployArgs memory a) {
        // Zero-address / zero-hash sanity. Any of these reaching production by
        // mistake would brick mint or setMetadata permanently.
        if (a.primaryA == address(0)) revert ZeroAddress();
        if (a.primaryB == address(0)) revert ZeroAddress();
        if (a.royaltyReceiver == address(0)) revert ZeroAddress();
        if (a.owner == address(0)) revert ZeroAddress();
        if (a.poemsHash == bytes32(0)) revert ZeroHash();
        if (a.traitsHash == bytes32(0)) revert ZeroHash();
        if (a.fontRegHash == bytes32(0)) revert ZeroHash();
        if (a.fontItaHash == bytes32(0)) revert ZeroHash();
        for (uint256 i = 0; i < MAX_SUPPLY; ++i) {
            if (hashes[i] == bytes32(0)) revert ZeroHash();
        }
        if (a.royaltyBps > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();

        svgHashes = hashes;
        poemsHash = a.poemsHash;
        traitsHash = a.traitsHash;
        fontRegHash = a.fontRegHash;
        fontItaHash = a.fontItaHash;
        primaryA = a.primaryA;
        primaryB = a.primaryB;
        _setDefaultRoyalty(a.royaltyReceiver, a.royaltyBps);
        _initializeOwner(a.owner);
        emit TreasuryChanged(a.primaryA, a.primaryB);
    }

    function name() public pure override returns (string memory) {
        return "Posts";
    }

    function symbol() public pure override returns (string memory) {
        return "POSTS";
    }

    // ─── owner setup (one-shot) ──────────────────────────────────────────

    /// @notice Write the committed poems / traits / font blobs to SSTORE2. One-shot.
    /// @dev    Reverts if hashes don't match constructor commitments.
    function setMetadata(
        bytes calldata poems,
        bytes calldata traits,
        bytes calldata fontReg,
        bytes calldata fontIta
    ) external onlyOwner {
        if (poemsPointer != address(0)) revert MetadataAlreadySet();
        if (keccak256(poems) != poemsHash) revert BadMetadataHash();
        if (keccak256(traits) != traitsHash) revert BadMetadataHash();
        if (keccak256(fontReg) != fontRegHash) revert BadMetadataHash();
        if (keccak256(fontIta) != fontItaHash) revert BadMetadataHash();
        poemsPointer    = SSTORE2.write(poems);
        traitsPointer   = SSTORE2.write(traits);
        fontRegPointer  = SSTORE2.write(fontReg);
        fontItaPointer  = SSTORE2.write(fontIta);
        emit MetadataSet(poemsPointer, traitsPointer, fontRegPointer, fontItaPointer);
    }

    // ─── public mint ──────────────────────────────────────────────────────

    /// @notice Mint the next sequential tokenId by submitting its committed SVG bytes.
    /// @dev    Blind sequential mint — minter doesn't pick. tokenId = totalMinted + 1.
    ///         Fee is split 50/50 between `primaryA` and `primaryB`.
    ///         Requires EXACT MINT_FEE (no refund logic — smart-wallet safe).
    function mint(bytes calldata svgBytes) external payable nonReentrant returns (uint256 tokenId) {
        if (!mintOpen) revert MintPaused();
        if (poemsPointer == address(0)) revert MetadataNotSet();
        if (msg.value != MINT_FEE) revert WrongFee();
        uint256 minted = totalMinted;
        if (minted >= MAX_SUPPLY) revert SoldOut();

        unchecked {
            tokenId = minted + 1;
        }
        if (keccak256(svgBytes) != svgHashes[minted]) revert BadSvg();

        address pointer = SSTORE2.write(svgBytes);
        artPointer[tokenId] = pointer;
        totalMinted = tokenId;

        _safeMint(msg.sender, tokenId);
        emit Minted(tokenId, msg.sender, pointer);

        // 50/50 fee split. `a = FEE / 2`, `b = FEE - a` keeps math exact even
        // if FEE ever becomes odd in wei. Both calls must succeed.
        uint256 aShare = MINT_FEE / 2;
        uint256 bShare = MINT_FEE - aShare;
        (bool okA,) = primaryA.call{value: aShare}("");
        if (!okA) revert PrimaryTransferFailed();
        (bool okB,) = primaryB.call{value: bShare}("");
        if (!okB) revert PrimaryTransferFailed();
    }

    /// @notice Returns a 222-byte array: byte[i] = 0x01 if tokenId (i+1) is minted, else 0x00.
    function mintedFlags() external view returns (bytes memory flags) {
        flags = new bytes(MAX_SUPPLY);
        for (uint256 i = 0; i < MAX_SUPPLY; ++i) {
            if (_ownerOf(i + 1) != address(0)) flags[i] = 0x01;
        }
    }

    // ─── on-chain views ───────────────────────────────────────────────────

    /// @notice Decode the (title, body) for `tokenId` from the on-chain poems blob.
    function poem(uint256 tokenId) public view returns (string memory title, string memory body) {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (poemsPointer == address(0)) revert MetadataNotSet();
        bytes memory data = SSTORE2.read(poemsPointer);

        uint256 offset = 0;
        for (uint256 i = 1; i < tokenId; ++i) {
            uint16 tl = _readU16(data, offset);
            offset += 2 + tl;
            uint16 pl = _readU16(data, offset);
            offset += 2 + pl;
        }
        uint16 titleLen = _readU16(data, offset);
        offset += 2;
        title = string(_slice(data, offset, titleLen));
        offset += titleLen;
        uint16 bodyLen = _readU16(data, offset);
        offset += 2;
        body = string(_slice(data, offset, bodyLen));
    }

    /// @notice Tone name + visual level for `tokenId`. Both immutable post-deploy.
    function tokenTraits(uint256 tokenId) public view returns (string memory tone, uint8 level) {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (traitsPointer == address(0)) revert MetadataNotSet();
        bytes memory data = SSTORE2.read(traitsPointer);
        uint256 offset = (tokenId - 1) * 2;
        tone = _toneName(uint8(data[offset]));
        level = uint8(data[offset + 1]);
    }

    /// @notice The raw on-chain SVG bytes for `tokenId` (post-mint), without
    ///         the inlined font-face style block. Use tokenURI for the full
    ///         render with fonts embedded.
    function tokenSvg(uint256 tokenId) public view returns (bytes memory) {
        address ptr = artPointer[tokenId];
        if (ptr == address(0)) revert NotMinted();
        return SSTORE2.read(ptr);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf(id) == address(0)) revert NotMinted();

        bytes memory svgWithFont = _renderSvg(id);
        (string memory title, string memory body) = poem(id);
        (string memory tone, uint8 level) = tokenTraits(id);

        string memory description =
            LibString.escapeJSON(string(abi.encodePacked(title, "\n\n", body)));

        bytes memory json = abi.encodePacked(
            '{"name":"Posts #',
            LibString.toString(id),
            '","description":"',
            description,
            '","image":"data:image/svg+xml;base64,',
            Base64.encode(svgWithFont),
            '","attributes":[{"trait_type":"Tone","value":"',
            tone,
            '"},{"trait_type":"Level","value":',
            LibString.toString(level),
            "}]}"
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    // Returns the on-chain SVG for `id` with the Inter font (regular + italic)
    // inlined as @font-face data URIs in a <defs><style> block. Renders Inter
    // in iframe/object contexts. In <img> contexts the browser ignores
    // @font-face and falls back to system sans-serif.
    function _renderSvg(uint256 id) internal view returns (bytes memory) {
        bytes memory svg = SSTORE2.read(artPointer[id]);
        bytes memory fontReg = SSTORE2.read(fontRegPointer);
        bytes memory fontIta = SSTORE2.read(fontItaPointer);

        // Splice the style block immediately after the opening <svg ...> tag.
        // The renderer always emits that tag as the very first thing.
        uint256 openEnd = _findByte(svg, 0x3e /* '>' */) + 1;

        bytes memory styleBlock = abi.encodePacked(
            '<defs><style>@font-face{font-family:"Inter";font-style:normal;src:url(data:font/otf;base64,',
            Base64.encode(fontReg),
            ');}@font-face{font-family:"Inter";font-style:italic;src:url(data:font/otf;base64,',
            Base64.encode(fontIta),
            ');}</style></defs>'
        );

        bytes memory out = new bytes(svg.length + styleBlock.length);
        for (uint256 i = 0; i < openEnd; ++i) out[i] = svg[i];
        for (uint256 i = 0; i < styleBlock.length; ++i) out[openEnd + i] = styleBlock[i];
        for (uint256 i = openEnd; i < svg.length; ++i) out[i + styleBlock.length] = svg[i];
        return out;
    }

    function _findByte(bytes memory data, uint8 b) private pure returns (uint256) {
        for (uint256 i = 0; i < data.length; ++i) {
            if (uint8(data[i]) == b) return i;
        }
        revert BadSvg(); // malformed SVG bytes (should never happen post-commit)
    }

    // ─── admin ────────────────────────────────────────────────────────────

    /// @notice Update royalty receiver / BPS. Capped at MAX_ROYALTY_BPS (10%).
    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (bps > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();
        _setDefaultRoyalty(receiver, bps);
    }

    /// @notice Update the two primary-sale recipients (mint fee 50/50 split).
    ///         Useful if a recipient address bricks or needs rotation.
    function setTreasury(address newA, address newB) external onlyOwner {
        if (newA == address(0) || newB == address(0)) revert ZeroAddress();
        primaryA = newA;
        primaryB = newB;
        emit TreasuryChanged(newA, newB);
    }

    /// @notice Open or pause public mint. Default at deploy is paused (false).
    ///         Flip to true at launch; can be re-paused if needed.
    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintOpenSet(open);
    }

    /// @notice Disable single-step ownership transfer. Forces use of the
    ///         2-step `requestOwnershipHandover` → `completeOwnershipHandover`
    ///         pattern, protecting against typo-bricking.
    function transferOwnership(address) public payable virtual override {
        revert UseHandover();
    }

    /// @notice Disable owner renounce. The contract has post-deploy admin
    ///         duties (royalty + treasury rotation) that should never be lost.
    function renounceOwnership() public payable virtual override {
        revert UseHandover();
    }

    // ─── ERC165 ───────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return ERC721.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    // ─── internals ────────────────────────────────────────────────────────

    function _readU16(bytes memory data, uint256 offset) private pure returns (uint16) {
        return (uint16(uint8(data[offset])) << 8) | uint16(uint8(data[offset + 1]));
    }

    function _slice(bytes memory data, uint256 start, uint256 len)
        private
        pure
        returns (bytes memory out)
    {
        out = new bytes(len);
        for (uint256 i = 0; i < len; ++i) out[i] = data[start + i];
    }

    /// @dev Must match the off-chain TONES ordering in render.mjs / build-onchain-data.mjs.
    function _toneName(uint8 idx) private pure returns (string memory) {
        if (idx == 0) return "aurora";
        if (idx == 1) return "halo";
        if (idx == 2) return "depthfog";
        if (idx == 3) return "threadline";
        if (idx == 4) return "crescent";
        if (idx == 5) return "prismbar";
        if (idx == 6) return "metaphysical";
        if (idx == 7) return "bleed";
        revert InvalidTokenId(); // unknown tone idx — should never happen post-commit
    }
}
