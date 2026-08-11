// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Unidraw is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 internal constant MAX_SUPPLY = 7777;
    uint256 internal constant MAX_MINTS_PER_WALLET = 7;
    uint256 internal constant MAX_DRAWING_DATA_BYTES = 64_000;
    uint256 internal constant REROLL_LIMIT = 128;
    uint96 internal constant ROYALTY_DENOMINATOR = 10_000;

    uint8 internal constant BACKGROUND_COUNT = 12;
    uint8 internal constant BODY_COUNT = 8;
    uint8 internal constant MANE_COUNT = 15;
    uint8 internal constant HORN_COUNT = 10;
    uint8 internal constant EYES_COUNT = 12;
    uint8 internal constant ACCESSORY_COUNT = 20;
    uint8 internal constant AURA_COUNT = 8;
    uint8 internal constant MARKINGS_COUNT = 10;

    enum Rarity {
        Common,
        Rare,
        Legendary,
        Mythic
    }

    struct TraitIndexes {
        uint8 background;
        uint8 body;
        uint8 mane;
        uint8 horn;
        uint8 eyes;
        uint8 accessory;
        uint8 aura;
        uint8 markings;
        uint8 rarity;
    }

    struct TokenTraits {
        uint8 backgroundIndex;
        uint8 bodyIndex;
        uint8 maneIndex;
        uint8 hornIndex;
        uint8 eyesIndex;
        uint8 accessoryIndex;
        uint8 auraIndex;
        uint8 markingsIndex;
        uint8 rarityIndex;
        string backgroundName;
        string bodyName;
        string maneName;
        string hornName;
        string eyesName;
        string accessoryName;
        string auraName;
        string markingsName;
        string rarityName;
    }

    uint256 public mintPrice = 0.0003 ether;
    bool public paused;
    bool public revealed = true;
    string public unrevealedURI;

    uint256 internal _totalMinted;
    address private _royaltyReceiver;
    uint96 private _royaltyFeeNumerator;

    mapping(uint256 tokenId => uint256 dna) public tokenDNA;
    mapping(uint256 tokenId => bytes32 hash) public drawingHash;
    mapping(bytes32 comboHash => bool used) public usedCombinations;
    mapping(address wallet => uint256 amount) public walletMinted;
    mapping(address account => bool allowed) public devMinters;
    mapping(address wallet => uint256 amount) public devMinted;

    event Minted(address indexed minter, uint256 indexed tokenId, Rarity rarity, bytes32 indexed drawingHash);

    error MintPaused();
    error SoldOut();
    error MaxWalletMintsReached();
    error IncorrectPayment(uint256 requiredPrice);
    error EmptyDrawing();
    error DrawingDataTooLarge();
    error DuplicateRerollFailed();
    error UnauthorizedDevMinter();
    error InvalidRoyaltyFee();
    error ZeroAddress();
    error WithdrawFailed();
    error NonexistentToken();

    constructor() ERC721("Unidraw", "UNIDRAW") Ownable(msg.sender) {
        _setDefaultRoyalty(msg.sender, 500);
    }

    function mint(bytes calldata drawingData) external payable nonReentrant returns (uint256 tokenId) {
        if (paused) revert MintPaused();
        if (walletMinted[msg.sender] >= MAX_MINTS_PER_WALLET) revert MaxWalletMintsReached();
        if (msg.value != mintPrice) revert IncorrectPayment(mintPrice);
        tokenId = _mintToken(msg.sender, msg.sender, drawingData);
        walletMinted[msg.sender] += 1;
    }

    function devMint(address to, bytes calldata drawingData) external nonReentrant returns (uint256 tokenId) {
        _requireDevMinter(to);
        tokenId = _mintToken(msg.sender, to, drawingData);
        devMinted[to] += 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        if (!revealed && bytes(unrevealedURI).length != 0) return unrevealedURI;

        string memory image = Base64.encode(bytes(_renderSVG(tokenId, tokenDNA[tokenId])));
        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name":"Unidraw #',
                    tokenId.toString(),
                    '","collection":"Unidraw","description":"Draw once. Mint an onchain pixel unicorn. Fully onchain SVG generated from deterministic DNA.","image":"data:image/svg+xml;base64,',
                    image,
                    '","attributes":[',
                    _attributesJson(tokenId),
                    "]}"
                )
            )
        );

        return string.concat("data:application/json;base64,", json);
    }

    function renderSVG(uint256 tokenId) external view returns (string memory) {
        _requireMinted(tokenId);
        return _renderSVG(tokenId, tokenDNA[tokenId]);
    }

    function tokenTraits(uint256 tokenId) external view returns (TokenTraits memory traits) {
        _requireMinted(tokenId);
        traits = _tokenTraits(tokenDNA[tokenId]);
    }

    function totalSupply() external view returns (uint256) {
        return _totalMinted;
    }

    function setDevMinter(address account, bool allowed) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        devMinters[account] = allowed;
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    function setRevealed(bool value) external onlyOwner {
        revealed = value;
    }

    function setUnrevealedURI(string calldata uri) external onlyOwner {
        unrevealedURI = uri;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function withdraw() external onlyOwner nonReentrant {
        _withdraw(payable(owner()));
    }

    function withdrawTo(address payable to) external onlyOwner nonReentrant {
        _withdraw(to);
    }

    function _mintToken(address minter, address to, bytes calldata drawingData) private returns (uint256 tokenId) {
        if (_totalMinted >= MAX_SUPPLY) revert SoldOut();
        if (drawingData.length == 0) revert EmptyDrawing();
        if (drawingData.length > MAX_DRAWING_DATA_BYTES) revert DrawingDataTooLarge();

        unchecked {
            tokenId = _totalMinted + 1;
        }
        bytes32 hash = keccak256(drawingData);

        // Demo/testnet randomness: deterministic and fully onchain, but block producers and users can bias it.
        // For production mainnet, replace this with Chainlink VRF or a commit-reveal randomness flow.
        uint256 seed = uint256(
            keccak256(abi.encodePacked(tokenId, to, minter, hash, block.prevrandao, blockhash(block.number - 1), address(this)))
        );
        (uint256 dna, bytes32 comboHash) = _uniqueDNA(seed);

        _totalMinted = tokenId;
        tokenDNA[tokenId] = dna;
        drawingHash[tokenId] = hash;
        usedCombinations[comboHash] = true;

        _safeMint(to, tokenId);

        emit Minted(minter, tokenId, _rarityOfDNA(dna), hash);
    }

    function _uniqueDNA(uint256 seed) private view returns (uint256 dna, bytes32 comboHash) {
        for (uint256 nonce; nonce < REROLL_LIMIT; ) {
            dna = nonce == 0 ? seed : uint256(keccak256(abi.encodePacked(seed, nonce)));
            comboHash = _comboHashFromDNA(dna);
            if (!usedCombinations[comboHash]) return (dna, comboHash);
            unchecked {
                nonce += 1;
            }
        }
        revert DuplicateRerollFailed();
    }

    function _comboHash(TraitIndexes memory t) private pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(t.background, t.body, t.mane, t.horn, t.eyes, t.accessory, t.aura, t.markings, t.rarity)
        );
    }

    function _comboHashFromDNA(uint256 dna) private pure returns (bytes32) {
        return _comboHash(_traitIndexesFromDNA(dna));
    }

    function _traitIndexesFromDNA(uint256 dna) private pure returns (TraitIndexes memory indexes) {
        indexes.background = uint8(dna % BACKGROUND_COUNT);
        indexes.body = uint8((dna >> 8) % BODY_COUNT);
        indexes.mane = uint8((dna >> 16) % MANE_COUNT);
        indexes.horn = uint8((dna >> 24) % HORN_COUNT);
        indexes.eyes = uint8((dna >> 32) % EYES_COUNT);
        indexes.accessory = uint8((dna >> 40) % ACCESSORY_COUNT);
        indexes.aura = uint8((dna >> 48) % AURA_COUNT);
        indexes.markings = uint8((dna >> 56) % MARKINGS_COUNT);
        indexes.rarity = uint8(_rarityOfDNA(dna));
    }

    function _rarityOfDNA(uint256 dna) private pure returns (Rarity) {
        return _rarityFromSeed(dna >> 88);
    }

    function _rarityFromSeed(uint256 seed) private pure returns (Rarity) {
        uint256 roll = seed % 10_000;
        if (roll < 7_500) return Rarity.Common;
        if (roll < 9_300) return Rarity.Rare;
        if (roll < 9_900) return Rarity.Legendary;
        return Rarity.Mythic;
    }

    function _renderSVG(uint256 tokenId, uint256 dna) private pure returns (string memory) {
        TraitIndexes memory t = _traitIndexesFromDNA(dna);
        Rarity rarity = Rarity(t.rarity);
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 640 640' shape-rendering='crispEdges'>",
            "<g transform='scale(10)'>",
            _backgroundSvg(t.background, rarity),
            _auraSvg(t.aura, rarity),
            _unicornSvg(t.body, t.mane, t.horn, t.eyes, t.accessory, t.markings),
            _rarityOverlay(rarity),
            "</g>",
            _tokenNumberSvg(tokenId),
            "</svg>"
        );
    }

    function _backgroundSvg(uint8 id, Rarity rarity) private pure returns (string memory) {
        (string memory base, string memory center, string memory edge) = _backgroundColors(id, rarity);
        return string.concat(
            "<defs><radialGradient id='b' cx='.5' cy='.38' r='.78'><stop offset='0' stop-color='",
            center,
            "'/><stop offset='.58' stop-color='",
            base,
            "'/><stop offset='1' stop-color='",
            edge,
            "'/></radialGradient></defs><rect width='64' height='64' fill='url(#b)'/>"
        );
    }

    function _auraSvg(uint8 id, Rarity rarity) private pure returns (string memory) {
        string memory color = _rarityColor(rarity);
        if (rarity == Rarity.Mythic) {
            return string.concat(
                "<rect x='17' y='52' width='31' height='2' fill='#1f2937' opacity='.22'/>",
                "<path d='M13 15H15V17H17V19H15V21H13V19H11V17H13Z' fill='",
                color,
                "' opacity='.72'/><path d='M53 18H55V20H57V22H55V24H53V22H51V20H53Z' fill='",
                color,
                "' opacity='.64'/>"
            );
        }
        if (id % 3 == 0) return "<rect x='17' y='52' width='31' height='2' fill='#1f2937' opacity='.2'/>";
        return string.concat(
            "<rect x='17' y='52' width='31' height='2' fill='#1f2937' opacity='.18'/><path d='M17 27C20 20 27 17 34 18C43 19 49 26 49 34C49 44 40 49 30 48C22 47 16 41 16 33Z' fill='",
            color,
            "' opacity='.07'/>"
        );
    }

    function _unicornSvg(
        uint8 body,
        uint8 mane,
        uint8 horn,
        uint8 eyes,
        uint8 accessory,
        uint8 markings
    ) private pure returns (string memory) {
        return string.concat(
            _tailSvg(mane),
            _bodySvg(body),
            _markingsSvg(markings),
            _maneSvg(mane),
            _hornSvg(horn),
            _eyesSvg(eyes),
            _accessorySvg(accessory)
        );
    }

    function _tailSvg(uint8 mane) private pure returns (string memory) {
        (string memory a, string memory b) = _maneColors(mane);
        return string.concat(
            "<path fill='",
            b,
            "' d='M13 32h8v4h-8zM11 35h7v7h-7zM10 39h4v4h-4z'/><path fill='",
            a,
            "' d='M14 32h7v3h-7zM10 38h4v3h-4z'/>"
        );
    }

    function _bodySvg(uint8 id) private pure returns (string memory) {
        (string memory main, string memory shadow, string memory highlight, string memory hoof) = _bodyColors(id);
        return string.concat(
            "<path fill='",
            shadow,
            "' d='M18 32h28v14H18zM21 29h21v5H21zM22 44h5v10h-5zM31 45h4v9h-4zM39 44h5v10h-5zM46 42h3v8h-3zM41 27h7v13h-7zM45 23h10v9H45zM53 26h4v4h-4zM47 20h3v3h-3z'/><path fill='",
            main,
            "' d='M19 33h26v11H19zM23 30h18v4H23zM23 44h4v9h-4zM32 45h3v8h-3zM40 44h4v9h-4zM46 42h2v7h-2zM42 28h5v11h-5zM46 24h9v8h-9zM54 27h3v3h-3zM48 21h2v2h-2z'/><path fill='",
            hoof,
            "' d='M22 53h6v2h-6zM30 53h6v2h-6zM38 53h7v2h-7zM45 49h4v2h-4z'/><path fill='",
            highlight,
            "' d='M23 31h12v2H23zM48 25h4v2h-4z'/>"
        );
    }

    function _maneSvg(uint8 id) private pure returns (string memory) {
        (string memory a, string memory b) = _maneColors(id);
        return string.concat(
            "<path fill='",
            b,
            "' d='M40 25h5v6h-5zM39 30h5v6h-5zM38 36h4v5h-4zM45 22h7v3h-7z'/><path fill='",
            a,
            "' d='M41 25h3v5h-3zM39 36h3v4h-3zM44 26h4v2h-4z'/>"
        );
    }

    function _hornSvg(uint8 id) private pure returns (string memory) {
        (string memory a, string memory b) = _hornColors(id);
        return string.concat(
            "<path fill='",
            b,
            "' d='M48 15h4v6h-4zM49 13h3v2h-3zM50 11h2v2h-2z'/><path fill='",
            a,
            "' d='M49 15h2v2h-2zM50 13h1v2h-1zM50 11h1v2h-1z'/>"
        );
    }

    function _eyesSvg(uint8 id) private pure returns (string memory) {
        string memory color = _eyeColor(id / 4);
        if (id % 4 == 1) return string.concat("<rect x='51' y='27' width='3' height='2' fill='", color, "'/>");
        if (id % 4 == 2) {
            return string.concat("<rect x='50' y='27' width='5' height='2' fill='", color, "'/><rect x='51' y='28' width='4' height='1' fill='#fff' opacity='.45'/>");
        }
        if (id % 4 == 3) {
            return string.concat("<rect x='51' y='26' width='2' height='2' fill='#fff'/><rect x='52' y='27' width='2' height='2' fill='", color, "'/>");
        }
        return string.concat("<rect x='51' y='27' width='2' height='2' fill='", color, "'/><rect x='52' y='27' width='1' height='1' fill='#fff'/>");
    }

    function _accessorySvg(uint8 id) private pure returns (string memory) {
        string memory color = _accessoryColor(id / 5);
        uint8 style = id % 5;
        if (style == 1) {
            return string.concat("<rect x='44' y='21' width='11' height='2' fill='", color, "'/><rect x='49' y='17' width='2' height='4' fill='#fff3b0'/>");
        }
        if (style == 2) {
            return string.concat("<rect x='43' y='15' width='14' height='2' fill='#e0f2fe'/><rect x='41' y='17' width='3' height='2' fill='", color, "'/><rect x='56' y='17' width='3' height='2' fill='", color, "'/>");
        }
        if (style == 3) return string.concat("<rect x='49' y='26' width='7' height='3' fill='", color, "'/><rect x='50' y='27' width='5' height='1' fill='#fff' opacity='.5'/>");
        if (style == 4) {
            return string.concat("<rect x='27' y='34' width='8' height='4' fill='", color, "'/><rect x='30' y='33' width='2' height='2' fill='#fff6cc'/>");
        }
        return string.concat("<rect x='41' y='39' width='5' height='2' fill='#e5e7eb'/><rect x='43' y='41' width='2' height='2' fill='", color, "'/>");
    }

    function _markingsSvg(uint8 id) private pure returns (string memory) {
        if (id == 1) return "<rect x='30' y='35' width='3' height='2' fill='#fff' opacity='.55'/>";
        if (id == 2) return "<rect x='24' y='37' width='2' height='2' fill='#fef3c7' opacity='.8'/><rect x='36' y='38' width='2' height='2' fill='#fef3c7' opacity='.7'/>";
        if (id == 3) return "<rect x='47' y='29' width='2' height='2' fill='#f0abfc' opacity='.75'/>";
        if (id == 4) return "<rect x='42' y='35' width='2' height='2' fill='#bae6fd' opacity='.8'/>";
        if (id == 5) return "<rect x='25' y='44' width='2' height='2' fill='#c4b5fd' opacity='.8'/>";
        if (id == 6) return "<rect x='34' y='34' width='2' height='2' fill='#fed7aa' opacity='.8'/>";
        if (id == 7) return "<rect x='48' y='28' width='1' height='3' fill='#fff' opacity='.75'/>";
        if (id == 8) return "<rect x='28' y='40' width='4' height='1' fill='#fff' opacity='.45'/>";
        if (id == 9) return "<rect x='39' y='35' width='3' height='2' fill='#fecdd3' opacity='.75'/>";
        return "";
    }

    function _rarityOverlay(Rarity rarity) private pure returns (string memory) {
        if (rarity == Rarity.Legendary) {
            return "<path d='M14 15H15V17H17V18H15V20H14V18H12V17H14Z' fill='#fff7ad' opacity='.85'/>";
        }
        if (rarity == Rarity.Mythic) {
            return
                "<path d='M10 12H12V14H14V16H12V18H10V16H8V14H10Z' fill='#fecdd3'/><path d='M54 48H55V50H57V51H55V53H54V51H52V50H54Z' fill='#fff' opacity='.8'/>";
        }
        return "";
    }

    function _tokenNumberSvg(uint256 tokenId) private pure returns (string memory) {
        return string.concat(
            "<text x='30' y='612' fill='#f8fafc' opacity='.32' font-family='monospace' font-size='14'>#",
            tokenId.toString(),
            "</text>"
        );
    }

    function _backgroundColors(uint8 id, Rarity rarity) private pure returns (string memory, string memory, string memory) {
        uint8 variant = id % 4;
        if (rarity == Rarity.Rare) {
            if (variant == 1) return ("#063a5f", "#1d9bd1", "#03111f");
            if (variant == 2) return ("#082f49", "#22d3ee", "#020617");
            if (variant == 3) return ("#172554", "#818cf8", "#060817");
            return ("#1e1b4b", "#6366f1", "#080817");
        }
        if (rarity == Rarity.Legendary) {
            if (variant == 1) return ("#5c3908", "#facc15", "#1a0b02");
            if (variant == 2) return ("#6b2f08", "#f59e0b", "#170702");
            if (variant == 3) return ("#713f12", "#fde047", "#1c1002");
            return ("#513008", "#fbbf24", "#120900");
        }
        if (rarity == Rarity.Mythic) {
            if (variant == 1) return ("#4a0711", "#ef4444", "#100207");
            if (variant == 2) return ("#3b0a2e", "#db2777", "#10020c");
            if (variant == 3) return ("#581c1c", "#fb7185", "#120303");
            return ("#450a0a", "#f43f5e", "#120303");
        }
        if (variant == 1) return ("#202632", "#64748b", "#06070a");
        if (variant == 2) return ("#22192f", "#7c3aed", "#07030d");
        if (variant == 3) return ("#172033", "#93c5fd", "#040711");
        return ("#18181b", "#3f3f46", "#050505");
    }

    function _bodyColors(uint8 id) private pure returns (string memory, string memory, string memory, string memory) {
        if (id == 1) return ("#f0f9ff", "#bae6fd", "#ffffff", "#38bdf8");
        if (id == 2) return ("#fff7ed", "#fed7aa", "#fffbeb", "#f59e0b");
        if (id == 3) return ("#fdf2f8", "#f9a8d4", "#ffffff", "#ec4899");
        if (id == 4) return ("#f0fdf4", "#bbf7d0", "#ffffff", "#22c55e");
        if (id == 5) return ("#e0e7ff", "#a5b4fc", "#f8fafc", "#6366f1");
        if (id == 6) return ("#fee2e2", "#fca5a5", "#fff1f2", "#ef4444");
        if (id == 7) return ("#faf5ff", "#d8b4fe", "#ffffff", "#a855f7");
        return ("#f8fafc", "#cbd5e1", "#ffffff", "#94a3b8");
    }

    function _maneColors(uint8 id) private pure returns (string memory, string memory) {
        if (id == 1) return ("#38bdf8", "#0ea5e9");
        if (id == 2) return ("#facc15", "#f59e0b");
        if (id == 3) return ("#fb7185", "#e11d48");
        if (id == 4) return ("#86efac", "#22c55e");
        if (id == 5) return ("#c084fc", "#7c3aed");
        if (id == 6) return ("#f8fafc", "#94a3b8");
        if (id == 7) return ("#f0abfc", "#06b6d4");
        if (id == 8) return ("#fdba74", "#ea580c");
        if (id == 9) return ("#67e8f9", "#2563eb");
        if (id == 10) return ("#f9a8d4", "#a855f7");
        if (id == 11) return ("#bbf7d0", "#14b8a6");
        if (id == 12) return ("#fde68a", "#fb7185");
        if (id == 13) return ("#ddd6fe", "#4338ca");
        if (id == 14) return ("#e2e8f0", "#64748b");
        return ("#f0abfc", "#06b6d4");
    }

    function _hornColors(uint8 id) private pure returns (string memory, string memory) {
        if (id == 1) return ("#bae6fd", "#0284c7");
        if (id == 2) return ("#fef3c7", "#facc15");
        if (id == 3) return ("#fecdd3", "#ef4444");
        if (id == 4) return ("#dcfce7", "#22c55e");
        if (id == 5) return ("#ede9fe", "#8b5cf6");
        if (id == 6) return ("#cffafe", "#06b6d4");
        if (id == 7) return ("#ffedd5", "#fb923c");
        if (id == 8) return ("#fae8ff", "#d946ef");
        if (id == 9) return ("#f8fafc", "#64748b");
        return ("#ffffff", "#cbd5e1");
    }

    function _rarityColor(Rarity rarity) private pure returns (string memory) {
        if (rarity == Rarity.Rare) return "#38bdf8";
        if (rarity == Rarity.Legendary) return "#facc15";
        if (rarity == Rarity.Mythic) return "#ef4444";
        return "#f8fafc";
    }

    function _eyeColor(uint8 id) private pure returns (string memory) {
        if (id == 1) return "#2563eb";
        if (id == 2) return "#f43f5e";
        return "#26364f";
    }

    function _accessoryColor(uint8 id) private pure returns (string memory) {
        if (id == 1) return "#38bdf8";
        if (id == 2) return "#facc15";
        if (id == 3) return "#fb7185";
        return "#a78bfa";
    }

    function _backgroundName(uint8 id, Rarity rarity) private pure returns (string memory) {
        uint8 variant = id % 4;
        if (rarity == Rarity.Rare) return _nameAt("Electric Indigo|Sapphire Blue|Cyan Pulse|Indigo Mist", variant);
        if (rarity == Rarity.Legendary) return _nameAt("Golden Amber|Solar Gold|Amber Orange|Warm Yellow", variant);
        if (rarity == Rarity.Mythic) return _nameAt("Crimson Rose|Ruby Red|Magenta Red|Rose Crimson", variant);
        return _nameAt("Charcoal Gray|Slate Moon|Muted Violet|Pale Sky", variant);
    }

    function _bodyName(uint8 id) private pure returns (string memory) {
        return _nameAt("Pearl White|Frost Blue|Vanilla Cream|Cotton Pink|Mint Shine|Lavender Milk|Rose Blush|Amethyst Silver", id);
    }

    function _maneName(uint8 id) private pure returns (string memory) {
        return _nameAt(
            "Bubblegum Cyan|Aqua Flow|Solar Gold|Crimson Rose|Emerald Stripe|Royal Purple|Silver Silk|Bubblegum Cyan|Peach Wave|Arctic Blue|Violet Dream|Mint Teal|Candy Gold|Midnight Fade|Silver Moon",
            id
        );
    }

    function _hornName(uint8 id) private pure returns (string memory) {
        return _nameAt("Crystal Horn|Sapphire Horn|Gold Horn|Ruby Horn|Emerald Horn|Amethyst Horn|Aqua Horn|Flame Horn|Candy Horn|Silver Horn", id);
    }

    function _eyesName(uint8 id) private pure returns (string memory) {
        uint8 palette = id / 4;
        uint8 style = id % 4;
        string memory tone = palette == 1 ? "Sapphire" : palette == 2 ? "Ruby" : "Midnight";
        if (style == 1) return string.concat(tone, " Wide Eyes");
        if (style == 2) return string.concat(tone, " Visor");
        if (style == 3) return string.concat(tone, " Spark Eyes");
        return string.concat(tone, " Eyes");
    }

    function _accessoryName(uint8 id) private pure returns (string memory) {
        uint8 palette = id / 5;
        uint8 style = id % 5;
        string memory tone = palette == 1 ? "Sky" : palette == 2 ? "Gold" : palette == 3 ? "Rose" : "Amethyst";
        if (style == 1) return string.concat(tone, " Crown");
        if (style == 2) return string.concat(tone, " Halo");
        if (style == 3) return string.concat(tone, " Visor");
        if (style == 4) return string.concat(tone, " Saddle Badge");
        return string.concat(tone, " Collar");
    }

    function _auraName(uint8 id, Rarity rarity) private pure returns (string memory) {
        if (rarity == Rarity.Mythic) return "Mythic Sparkles";
        if (id % 3 == 0) return "None";
        if (rarity == Rarity.Rare) return "Sky Aura";
        if (rarity == Rarity.Legendary) return "Gold Aura";
        return "Soft White Aura";
    }

    function _markingsName(uint8 id) private pure returns (string memory) {
        return _nameAt(
            "None|Pearl Body Mark|Golden Star Marks|Rose Cheek Mark|Aqua Diamond Mark|Violet Leg Mark|Amber Sparkle Mark|Pearl Face Stripe|Silver Wave Mark|Rose Body Mark",
            id
        );
    }

    function _tokenTraits(uint256 dna) private pure returns (TokenTraits memory traits) {
        TraitIndexes memory i = _traitIndexesFromDNA(dna);
        Rarity rarity = Rarity(i.rarity);
        traits.backgroundIndex = i.background;
        traits.bodyIndex = i.body;
        traits.maneIndex = i.mane;
        traits.hornIndex = i.horn;
        traits.eyesIndex = i.eyes;
        traits.accessoryIndex = i.accessory;
        traits.auraIndex = i.aura;
        traits.markingsIndex = i.markings;
        traits.rarityIndex = i.rarity;
        traits.backgroundName = _backgroundName(i.background, rarity);
        traits.bodyName = _bodyName(i.body);
        traits.maneName = _maneName(i.mane);
        traits.hornName = _hornName(i.horn);
        traits.eyesName = _eyesName(i.eyes);
        traits.accessoryName = _accessoryName(i.accessory);
        traits.auraName = _auraName(i.aura, rarity);
        traits.markingsName = _markingsName(i.markings);
        traits.rarityName = _rarityName(rarity);
    }

    function _attributesJson(uint256 tokenId) private view returns (string memory) {
        TokenTraits memory t = _tokenTraits(tokenDNA[tokenId]);
        return string.concat(
            string.concat(
                '{"trait_type":"Rarity","value":"',
                t.rarityName,
                '"},{"trait_type":"Background","value":"',
                t.backgroundName,
                '"},{"trait_type":"Body","value":"',
                t.bodyName,
                '"},{"trait_type":"Mane","value":"',
                t.maneName,
                '"},{"trait_type":"Horn","value":"',
                t.hornName,
                '"}'
            ),
            string.concat(
                ',{"trait_type":"Eyes","value":"',
                t.eyesName,
                '"},{"trait_type":"Accessory","value":"',
                t.accessoryName,
                '"},{"trait_type":"Aura","value":"',
                t.auraName,
                '"},{"trait_type":"Markings","value":"',
                t.markingsName,
                '"},{"trait_type":"Drawing Hash","value":"',
                Strings.toHexString(uint256(drawingHash[tokenId]), 32),
                '"}'
            )
        );
    }

    function _rarityName(Rarity rarity) private pure returns (string memory) {
        if (rarity == Rarity.Rare) return "Rare";
        if (rarity == Rarity.Legendary) return "Legendary";
        if (rarity == Rarity.Mythic) return "Mythic";
        return "Common";
    }

    function _nameAt(string memory names, uint8 id) private pure returns (string memory) {
        bytes memory data = bytes(names);
        uint256 start;
        uint8 index;

        for (uint256 cursor; cursor <= data.length; ) {
            if (cursor == data.length || data[cursor] == "|") {
                if (index == id) {
                    bytes memory value = new bytes(cursor - start);
                    for (uint256 i; i < value.length; ) {
                        value[i] = data[start + i];
                        unchecked {
                            i += 1;
                        }
                    }
                    return string(value);
                }
                start = cursor + 1;
                index += 1;
            }
            unchecked {
                cursor += 1;
            }
        }

        return "";
    }

    function _withdraw(address payable to) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = address(this).balance;
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
    }

    function _requireDevMinter(address to) private view {
        if (msg.sender != owner() && !devMinters[msg.sender]) revert UnauthorizedDevMinter();
        if (to == address(0)) revert ZeroAddress();
    }

    function _setDefaultRoyalty(address receiver, uint96 feeNumerator) private {
        if (receiver == address(0)) revert ZeroAddress();
        if (feeNumerator > ROYALTY_DENOMINATOR) revert InvalidRoyaltyFee();
        _royaltyReceiver = receiver;
        _royaltyFeeNumerator = feeNumerator;
    }

    function _requireMinted(uint256 tokenId) private view {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentToken();
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        return (_royaltyReceiver, (salePrice * _royaltyFeeNumerator) / ROYALTY_DENOMINATOR);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721) returns (bool) {
        return interfaceId == 0x2a55205a || super.supportsInterface(interfaceId);
    }
}
