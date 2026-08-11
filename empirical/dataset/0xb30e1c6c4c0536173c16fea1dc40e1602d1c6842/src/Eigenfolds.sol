// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// =============================================================================
// SSTORE2 — store data as deployed contract bytecode instead of in storage.
// -----------------------------------------------------------------------------
// SSTORE costs ~22,100 gas per 32 bytes. Deploying contract bytecode costs
// ~200 gas per byte. For the ~24 KB render script, storage-as-string costs
// roughly 25M gas (over most RPC providers' per-tx limit). Storage-as-bytecode
// costs roughly 5M. We deploy the script as a "data contract" whose runtime
// bytecode IS the script (with a STOP opcode prepended so it can't be called),
// then read it back with EXTCODECOPY.
// =============================================================================
library SSTORE2 {
    error DeployFailed();
    error PointerEmpty();
    error DataTooLarge();

    /// @notice Deploy `data` as the runtime bytecode of a new contract.
    /// @dev The init code is:
    ///   PUSH2 <runtime_size> DUP1 PUSH1 0x0A RETURNDATASIZE CODECOPY RETURNDATASIZE RETURN STOP <data>
    /// At deployment, this copies the bytes after offset 0x0A (the leading STOP + data) into memory
    /// and returns them, making them the deployed contract's runtime code. The leading STOP byte
    /// ensures the data contract can't accidentally be invoked as executable code.
    function write(bytes memory data) internal returns (address pointer) {
        uint256 runtimeSize = data.length + 1; // +1 for the leading STOP byte
        if (runtimeSize > 0xFFFF) revert DataTooLarge();

        bytes memory initCode = abi.encodePacked(
            hex"61",                  // PUSH2
            uint16(runtimeSize),      // 2-byte runtime size
            hex"80600A3D393DF300",    // DUP1 PUSH1 0x0A RETURNDATASIZE CODECOPY RETURNDATASIZE RETURN STOP
            data
        );

        assembly {
            pointer := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (pointer == address(0)) revert DeployFailed();
    }

    function read(address pointer) internal view returns (bytes memory data) {
        uint256 size;
        assembly { size := extcodesize(pointer) }
        if (size == 0) revert PointerEmpty();
        // Skip the leading STOP byte.
        data = new bytes(size - 1);
        assembly {
            extcodecopy(pointer, add(data, 0x20), 1, sub(size, 1))
        }
    }
}

// =============================================================================
// EigenfoldsScripts
// -----------------------------------------------------------------------------
// Holds the JavaScript render code as deployed bytecode via SSTORE2. The
// `script()` accessor and `getScript()` both return the same string so the
// public interface stays compatible with code that expected a plain string
// storage variable. The script reads parameters from `window.EIGEN` and draws
// the fractal.
// =============================================================================
contract EigenfoldsScripts {
    /// @notice Address of the SSTORE2 data contract holding the script bytes.
    address public scriptPointer;
    address public immutable owner;
    bool public frozen;

    error NotOwner();
    error AlreadyFrozen();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory _script) {
        owner = msg.sender;
        scriptPointer = SSTORE2.write(bytes(_script));
    }

    /// @notice Returns the full render script as a string.
    function getScript() public view returns (string memory) {
        return string(SSTORE2.read(scriptPointer));
    }

    /// @notice Alias for backwards-compatibility with the previous storage-string layout.
    function script() external view returns (string memory) {
        return getScript();
    }

    function updateScript(string memory _script) external onlyOwner {
        if (frozen) revert AlreadyFrozen();
        scriptPointer = SSTORE2.write(bytes(_script));
    }

    function freeze() external onlyOwner {
        frozen = true;
    }
}

interface IScripts {
    function getScript() external view returns (string memory);
}

// =============================================================================
// Eigenfolds
// -----------------------------------------------------------------------------
// 9600 fully-enumerated on-chain fractals. The token ID itself encodes the
// piece's parameters:
//
//   tokenId = preset · 2400 + variation · 24 + palette · 4 + (density − 1)
//
//   preset    ∈ {0..3}    — 4 Pisot families
//   variation ∈ {0..99}   — 100 distinct 4×4 matrices per family
//   palette   ∈ {0..5}    — 6 colour worlds
//   density   ∈ {1..4}    — 4 render densities
//
// This means the contract stores no per-token data; the four numbers needed to
// render any piece are decoded from its token ID. The collection is a pure
// enumeration — every combination of (family, variation, palette, density)
// exists as exactly one piece.
//
// Compatible with the Verse marketplace pattern: Verse's settlement wallet
// (mintingManager) calls `mint(buyer, tokenId)` or `mintBatch(...)` after the
// buyer pays off-contract. Direct user mint and on-contract pricing are
// intentionally absent — Verse owns the mint window, pricing, and payment
// custody on their side.
// =============================================================================
contract Eigenfolds is ERC721, Ownable {
    using Strings for uint256;

    // ----- Collection dimensions -----
    uint256 public constant PRESETS    = 4;
    uint256 public constant VARIATIONS = 100;
    uint256 public constant PALETTES   = 6;
    uint256 public constant DENSITIES  = 4;
    uint256 public constant MAX_SUPPLY = PRESETS * VARIATIONS * PALETTES * DENSITIES; // 9600

    // ----- State -----
    /// @notice Wallet authorised to call `mint` / `mintBatch`. In production
    ///         this is Verse's settlement wallet.
    address public mintingManager;
    address public scriptsContract;

    mapping(uint256 => bool) private _minted;
    uint256 public totalMinted;

    // ----- Mint-order numbering -----
    // Each piece's display name is "Eigenfold #N" where N is the order in which
    // it was minted (1-indexed). These mappings record the assignment.
    //
    //   mintOrderOf[tokenId]       => N    (the piece's display number)
    //   tokenIdByMintOrder[N]      => tokenId
    //
    // Set inside _doMint before _safeMint, so the name is always defined when
    // a marketplace queries tokenURI.
    mapping(uint256 => uint256) public mintOrderOf;
    mapping(uint256 => uint256) public tokenIdByMintOrder;

    // ----- Events & errors -----
    event MintingManagerUpdated(address indexed previous, address indexed current);
    event PieceMinted(address indexed to, uint256 indexed tokenId, uint256 indexed mintOrder);

    error InvalidTokenId();
    error InvalidParams();
    error AlreadyMinted();
    error NotMinter();
    error LengthMismatch();
    error ZeroAddress();

    modifier onlyMinter() {
        if (msg.sender != mintingManager) revert NotMinter();
        _;
    }

    constructor(
        address initialOwner,
        address _scriptsContract,
        address _mintingManager
    ) ERC721("Eigenfolds", "EFLD") Ownable(initialOwner) {
        scriptsContract = _scriptsContract;
        mintingManager  = _mintingManager;
        emit MintingManagerUpdated(address(0), _mintingManager);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Update the wallet authorised to call `mint` / `mintBatch`.
    ///         Use this to point at a new Verse settlement wallet if needed.
    function setMintingManager(address _mintingManager) external onlyOwner {
        if (_mintingManager == address(0)) revert ZeroAddress();
        address previous = mintingManager;
        mintingManager = _mintingManager;
        emit MintingManagerUpdated(previous, _mintingManager);
    }

    function setScriptsContract(address _scripts) external onlyOwner {
        scriptsContract = _scripts;
    }

    // -------------------------------------------------------------------------
    // Mint — gated to the minting manager (Verse). The contract does not
    // collect ETH; Verse handles payment off-contract.
    // -------------------------------------------------------------------------

    /// @notice Mint a single piece to `to`. Verse calls this from their
    ///         settlement wallet after the buyer pays on the Verse side.
    function mint(address to, uint256 tokenId) external onlyMinter {
        _doMint(to, tokenId);
    }

    /// @notice Batch-mint multiple pieces. `to[i]` receives `tokenIds[i]`.
    ///         Verse calls this when settling multiple primary sales together.
    function mintBatch(address[] calldata to, uint256[] calldata tokenIds) external onlyMinter {
        uint256 len = to.length;
        if (len != tokenIds.length) revert LengthMismatch();
        for (uint256 i = 0; i < len; ) {
            _doMint(to[i], tokenIds[i]);
            unchecked { ++i; }
        }
    }

    function _doMint(address to, uint256 tokenId) internal {
        if (tokenId >= MAX_SUPPLY) revert InvalidTokenId();
        if (_minted[tokenId]) revert AlreadyMinted();
        _minted[tokenId] = true;
        unchecked { totalMinted += 1; }
        // Assign this piece's display number before _safeMint, so the
        // ERC721 receiver hook can read it back from tokenURI if it wants to.
        uint256 mintOrder = totalMinted;
        mintOrderOf[tokenId] = mintOrder;
        tokenIdByMintOrder[mintOrder] = tokenId;
        _safeMint(to, tokenId);
        emit PieceMinted(to, tokenId, mintOrder);
    }

    // -------------------------------------------------------------------------
    // Token ID ↔ parameter encoding
    // -------------------------------------------------------------------------

    /// @notice Decode a token ID into its four parameters.
    /// @return preset    Pisot family, 0..3.
    /// @return variation Matrix index within the family, 0..99.
    /// @return palette   Colour world, 0..5.
    /// @return density   Render density, 1..4.
    function paramsOf(uint256 tokenId)
        public
        pure
        returns (uint8 preset, uint8 variation, uint8 palette, uint8 density)
    {
        if (tokenId >= MAX_SUPPLY) revert InvalidTokenId();
        uint256 t = tokenId;
        preset    = uint8(t / (VARIATIONS * PALETTES * DENSITIES));            // / 2400
        t = t % (VARIATIONS * PALETTES * DENSITIES);
        variation = uint8(t / (PALETTES * DENSITIES));                         // / 24
        t = t % (PALETTES * DENSITIES);
        palette   = uint8(t / DENSITIES);                                       // / 4
        density   = uint8(t % DENSITIES) + 1;
    }

    /// @notice Compose a token ID from its four parameters.
    function tokenIdOf(uint8 preset, uint8 variation, uint8 palette, uint8 density)
        public
        pure
        returns (uint256)
    {
        if (preset >= PRESETS || variation >= VARIATIONS || palette >= PALETTES
            || density < 1 || density > DENSITIES) revert InvalidParams();
        return uint256(preset) * (VARIATIONS * PALETTES * DENSITIES)
             + uint256(variation) * (PALETTES * DENSITIES)
             + uint256(palette) * DENSITIES
             + uint256(density - 1);
    }

    function isMinted(uint256 tokenId) external view returns (bool) {
        if (tokenId >= MAX_SUPPLY) revert InvalidTokenId();
        return _minted[tokenId];
    }

    // -------------------------------------------------------------------------
    // tokenURI — fully on-chain
    // -------------------------------------------------------------------------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        (uint8 preset, uint8 variation, uint8 palette, uint8 density) = paramsOf(tokenId);

        string memory presetName  = _presetName(preset);
        string memory paletteName = _paletteName(palette);
        string memory varStr      = uint256(variation + 1).toString();
        string memory orderStr    = mintOrderOf[tokenId].toString();

        bytes memory html = _buildHTML(preset, variation, palette, density);
        string memory htmlB64 = Base64.encode(html);

        bytes memory svg = _buildImage(preset, palette, density, mintOrderOf[tokenId], presetName, paletteName);
        string memory svgB64 = Base64.encode(svg);

        // Name follows mint order: "Eigenfold #1", "Eigenfold #2", … The token
        // ID (which encodes the parametric identity) is preserved as a trait.
        // `image` is a small SVG poster (palette swatches + piece info) used as
        // the thumbnail. `animation_url` is the interactive on-chain render.
        bytes memory json = abi.encodePacked(
            '{"name":"Eigenfold #', orderStr,
            '","description":"', _description(),
            '","image":"data:image/svg+xml;base64,', svgB64,
            '","animation_url":"data:text/html;base64,', htmlB64,
            '","attributes":[',
                '{"trait_type":"Family","value":"', presetName, '"},',
                '{"trait_type":"Variation","value":', varStr, '},',
                '{"trait_type":"Palette","value":"', paletteName, '"},',
                '{"trait_type":"Density","value":', uint256(density).toString(), '},',
                '{"trait_type":"Mint Order","display_type":"number","value":', orderStr, '},',
                '{"trait_type":"Token ID","display_type":"number","value":', tokenId.toString(), '}',
            ']}'
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    // -------------------------------------------------------------------------
    // SVG thumbnail (image field)
    // -------------------------------------------------------------------------

    /// @notice Build a small static SVG poster for the piece — used as the
    ///         `image` field in tokenURI. Shows palette swatches in a diamond
    ///         arrangement plus the piece name and metadata.
    function _buildImage(
        uint8 preset,
        uint8 palette,
        uint8 density,
        uint256 mintOrder,
        string memory presetName,
        string memory paletteName
    ) internal pure returns (bytes memory) {
        string[4] memory c = _paletteHex(palette);
        preset; // silence "unused" warning — preset is implied by presetName
        return abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600">',
                '<rect width="600" height="600" fill="#0a0a0c"/>',
                '<text x="300" y="62" text-anchor="middle" fill="#5a5a5a" '
                    'font-family="monospace" font-size="11" letter-spacing="4">EIGENFOLDS</text>',
                '<circle cx="300" cy="195" r="66" fill="', c[0], '"/>',
                '<circle cx="180" cy="315" r="66" fill="', c[1], '"/>',
                '<circle cx="420" cy="315" r="66" fill="', c[2], '"/>',
                '<circle cx="300" cy="435" r="66" fill="', c[3], '"/>',
                '<text x="300" y="530" text-anchor="middle" fill="#ececef" '
                    'font-family="monospace" font-size="28">Eigenfold #', mintOrder.toString(), '</text>',
                '<text x="300" y="560" text-anchor="middle" fill="#9a9a9a" '
                    'font-family="monospace" font-size="14">',
                    presetName, ' - ', paletteName, ' - density ', uint256(density).toString(),
                '</text>',
            '</svg>'
        );
    }

    function _paletteHex(uint8 p) internal pure returns (string[4] memory) {
        if (p == 0) return ["#7EE8FA", "#7E57C2", "#EF6C9F", "#FFCA28"]; // Aurora
        if (p == 1) return ["#FF6B6B", "#FFA726", "#42A5F5", "#AB47BC"]; // Sunset
        if (p == 2) return ["#26C6DA", "#5C6BC0", "#7E57C2", "#EF6C9F"]; // Ocean
        if (p == 3) return ["#EF5350", "#FF7043", "#FFCA28", "#FFEE58"]; // Ember
        if (p == 4) return ["#7CB342", "#66BB6A", "#26A69A", "#7986CB"]; // Forest
        return ["#E6E1D2", "#AAA08C", "#786C5C", "#3C342A"];             // Bone
    }

    function _description() internal pure returns (string memory) {
        return "A complete enumeration of every variation of every Pisot family, in every palette, at every density. 9600 three-dimensional fractals, each rendered on-chain.";
    }

    function _buildHTML(uint8 preset, uint8 variation, uint8 palette, uint8 density) internal view returns (bytes memory) {
        string memory script = IScripts(scriptsContract).getScript();
        return abi.encodePacked(
            '<!DOCTYPE html><html><head><meta charset="utf-8">'
            '<style>html,body{margin:0;padding:0;background:#0a0a0c;overflow:hidden;width:100%;height:100%}'
            'canvas{display:block;width:100vw;height:100vh;cursor:grab}canvas:active{cursor:grabbing}</style>'
            '</head><body><canvas id="c"></canvas><script>',
            'window.EIGEN={p:',  uint256(preset).toString(),
            ',v:',                uint256(variation).toString(),
            ',c:',                uint256(palette).toString(),
            ',d:',                uint256(density).toString(),
            '};',
            script,
            '</script></body></html>'
        );
    }

    function _presetName(uint8 p) internal pure returns (string memory) {
        if (p == 0) return "Tetranacci";
        if (p == 1) return "Pillar";
        if (p == 2) return "Hawthorn";
        return "Bowed";
    }

    function _paletteName(uint8 p) internal pure returns (string memory) {
        if (p == 0) return "Aurora";
        if (p == 1) return "Sunset";
        if (p == 2) return "Ocean";
        if (p == 3) return "Ember";
        if (p == 4) return "Forest";
        return "Bone";
    }
}
