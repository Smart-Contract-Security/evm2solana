// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "../utils/Base64.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/// @notice Minimal interface NormlAssets uses to read live stake state from NormlForUs.
interface INormlForUsReader {
    function tokensStakedToToken(uint256 tokenId) external view returns (uint256);
}

/// @notice Minimal interface NormlAssets uses to read NormlForMe NFT-token state.
interface INormlForMeReader {
    function lockedAmount(uint256 tokenId) external view returns (uint256);
    function determinismHash(uint256 tokenId) external view returns (bytes32);
}

/// @title NormlAssets
/// @notice SSTORE2-backed on-chain asset store + animation HTML builder for the NORML collection.
/// @dev Owned, settable wiring (`normlForUs`, `normlToken`, `normlForMe`) so this contract
///      can be deployed first and later pointed at the live ERC-721 and ERC-20.
///      Canonical home for all chunk storage, animation URI construction, image data URI
///      construction, and the per-block deterministic liquid render position picker.
/// @author jiwa
contract NormlAssets {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant ARTWORK_COUNT = 9;
    uint256 public constant BIDDERS_EDITION_ID = 8;

    /// @notice Pixel count returned by liquid animationURI when no `normlToken` is wired.
    uint256 public constant DEFAULT_LIQUID_PIXELS = 10_000;
    /// @notice Pixel count returned by 1/1 animationURI when no `normlForUs` is wired.
    uint256 public constant DEFAULT_1OF1_PIXELS = 1_000_000;

    /// @notice Canvas width per artwork (whole pixels; fractional rounded down from spec).
    uint16[9] public CANVAS_W = [1644, 2358, 1932, 1830, 2000, 1800, 2457, 1918, 1800];
    /// @notice Canvas height per artwork (whole pixels; fractional rounded down from spec).
    uint16[9] public CANVAS_H = [2595, 1701, 1730, 1842, 2198, 1800, 1843, 1918, 1360];

    /// @notice Artwork names.
    string[9] internal _artworkNames = [
        "grasping for reach",
        "implied tone",
        "stream sunk cost",
        "or sorry that",
        "red white blau light",
        "too many requests",
        "type send regret",
        "undo scaffolding",
        "lost in draft"
    ];

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address public owner;

    /// @notice Live ERC-721 NormlForUs contract (read source for `tokensStakedToToken`).
    ///         Zero until set via `setNormlForUs`. When zero, animationURIForUs uses defaults.
    address public normlForUs;

    /// @notice ERC-20 NORML Liquid Edition token (read source for holder pixel balance).
    ///         Zero until set via `setNormlToken`. When zero, animationURILiquid uses defaults.
    address public normlToken;

    /// @notice NormlForMe companion contract (read source for stake records).
    ///         Zero until set via `setNormlForMe`. Required for animationURIForMe.
    address public normlForMe;

    /// @notice SSTORE2 chunks for shared HTML wrapper.
    address[] internal _htmlChunks;

    /// @notice SSTORE2 chunks for per-artwork asset bundles, indexed by tokenId (0..8).
    mapping(uint256 => address[]) internal _assetChunks;

    /// @notice SSTORE2 chunks for the `image` field of token metadata.
    ///         Slot 0 = Liquid Edition image. Slot N (1..9) = tokenId N-1 image (0..8).
    mapping(uint256 => address[]) internal _imageChunks;

    /// @notice Optional per-1/1 description override. If empty, callers use a default.
    mapping(uint256 => string) internal _artworkDescriptions;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotOwner();
    error InvalidTokenId();
    error InvalidSlot();
    error InvalidArtworkId();
    error NormlForMeNotSet();
    error InvalidStakeIndex();
    error ZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event NormlForUsUpdated(address indexed previous, address indexed current);
    event NormlTokenUpdated(address indexed previous, address indexed current);
    event NormlForMeUpdated(address indexed previous, address indexed current);
    event SharedAssetsSet(uint256 chunkCount);
    event TokenAssetsSet(uint256 indexed tokenId, uint256 chunkCount);
    event ImageAssetsSet(uint256 indexed slot, uint256 chunkCount);
    event ArtworkDescriptionSet(uint256 indexed tokenId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         ADMIN/WIRING                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setNormlForUs(address newAddr) external onlyOwner {
        emit NormlForUsUpdated(normlForUs, newAddr);
        normlForUs = newAddr;
    }

    function setNormlToken(address newAddr) external onlyOwner {
        emit NormlTokenUpdated(normlToken, newAddr);
        normlToken = newAddr;
    }

    function setNormlForMe(address newAddr) external onlyOwner {
        emit NormlForMeUpdated(normlForMe, newAddr);
        normlForMe = newAddr;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ASSET UPLOADS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the shared HTML wrapper chunks (base64-encoded, padded to 3-byte boundary).
    function setSharedAssets(address[] calldata htmlChunks) external onlyOwner {
        _htmlChunks = htmlChunks;
        emit SharedAssetsSet(htmlChunks.length);
    }

    /// @notice Set asset chunks for one artwork (tokenId 0..8, base64-encoded).
    function setTokenAssets(uint256 tokenId, address[] calldata assetChunks) external onlyOwner {
        if (tokenId >= ARTWORK_COUNT) revert InvalidTokenId();
        _assetChunks[tokenId] = assetChunks;
        emit TokenAssetsSet(tokenId, assetChunks.length);
    }

    /// @notice Batch set asset chunks for all 9 artworks.
    function setAllTokenAssets(address[][] calldata allAssetChunks) external onlyOwner {
        if (allAssetChunks.length != ARTWORK_COUNT) revert InvalidTokenId();
        for (uint256 i = 0; i < ARTWORK_COUNT; i++) {
            _assetChunks[i] = allAssetChunks[i];
            emit TokenAssetsSet(i, allAssetChunks[i].length);
        }
    }

    /// @notice Set image chunks for slot N (slot 0 = liquid edition image, slot N+1 = tokenId N image).
    /// @dev    Chunks are concatenated as raw bytes to form a complete `data:...` string.
    function setImageAssets(uint256 slot, address[] calldata imageChunks) external onlyOwner {
        if (slot > ARTWORK_COUNT) revert InvalidSlot();
        _imageChunks[slot] = imageChunks;
        emit ImageAssetsSet(slot, imageChunks.length);
    }

    /// @notice Set the description override for a 1/1 artwork.
    function setArtworkDescription(uint256 tokenId, string calldata description_) external onlyOwner {
        if (tokenId >= ARTWORK_COUNT) revert InvalidTokenId();
        _artworkDescriptions[tokenId] = description_;
        emit ArtworkDescriptionSet(tokenId);
    }

    /// @notice Return all shared HTML chunk addresses (for migration / inspection).
    function getSharedChunks() external view returns (address[] memory) {
        return _htmlChunks;
    }

    /// @notice Return all asset chunk addresses for one artwork (for migration / inspection).
    function getTokenChunks(uint256 tokenId) external view returns (address[] memory) {
        if (tokenId >= ARTWORK_COUNT) revert InvalidTokenId();
        return _assetChunks[tokenId];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       READ ACCESSORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function artworkName(uint256 tokenId) external view returns (string memory) {
        if (tokenId >= ARTWORK_COUNT) revert InvalidArtworkId();
        return _artworkNames[tokenId];
    }

    function artworkDescription(uint256 tokenId) external view returns (string memory) {
        if (tokenId >= ARTWORK_COUNT) revert InvalidArtworkId();
        return _artworkDescriptions[tokenId];
    }

    /// @notice Per-artwork canvas dimensions (whole pixels).
    function canvas(uint256 tokenId) external view returns (uint16 width, uint16 height) {
        if (tokenId >= ARTWORK_COUNT) revert InvalidArtworkId();
        return (CANVAS_W[tokenId], CANVAS_H[tokenId]);
    }

    /// @notice Max stakeable pixels for an artwork (canvas width * height).
    function maxPixels(uint256 tokenId) public view returns (uint256) {
        if (tokenId >= ARTWORK_COUNT) revert InvalidArtworkId();
        return uint256(CANVAS_W[tokenId]) * uint256(CANVAS_H[tokenId]);
    }

    /// @notice Image data URI for slot (0 = liquid, slot = tokenId+1 for 1/1s).
    ///         Returns empty string when no chunks are uploaded — caller falls back to SVG.
    function imageDataUri(uint256 slot) external view returns (string memory) {
        if (slot > ARTWORK_COUNT) revert InvalidSlot();
        address[] storage chunks = _imageChunks[slot];
        if (chunks.length == 0) return "";
        return _readChunkedString(chunks);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ANIMATION URIs                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Liquid edition animation HTML.
    /// @dev Artwork id AND view-window position are both derived from `blockhash(block.number-1)`
    ///      so all holders viewing in the same block see the same artwork+position pair
    ///      ("consensus moments"). `holder` only feeds the pixel count via NORML balance.
    ///
    ///      Max-staked artworks are skipped: if the seed lands on an artwork whose
    ///      staked pixels have reached its canvas cap, we rotate forward through the
    ///      remaining artworks until we find one with room. As soon as that artwork
    ///      is un-staked back below its cap it re-enters the selection pool. If every
    ///      artwork is simultaneously full, we keep the original seed pick (the
    ///      position picker still clamps cleanly at the cap).
    function animationURILiquid(address holder) external view returns (string memory) {
        // blockhash returns bytes32(0) in eth_call on most RPCs; mix in prevrandao
        // (the RANDAO value, available in eth_call) and holder address so the seed
        // is live and differs per holder.
        bytes32 seed = keccak256(abi.encodePacked(block.prevrandao, holder));
        uint256 artworkId = _pickAvailableArtwork(uint256(seed) % ARTWORK_COUNT);
        uint256 holderPixels = _liquidPixels(holder);
        uint256 stakedPixels = _stakedPixels(artworkId);
        (uint16 xBps, uint16 yBps) = _randomPosition(seed, artworkId, stakedPixels);

        return _buildAnimationDataUri(
            artworkId,
            _injectionLiquid(artworkId, holderPixels, xBps, yBps)
        );
    }

    /// @notice 1/1 + bidder's edition animation HTML.
    function animationURIForUs(uint256 tokenId) external view returns (string memory) {
        if (tokenId > BIDDERS_EDITION_ID) revert InvalidTokenId();
        uint256 pixels = _tokenStakedPixels(tokenId);
        return _buildAnimationDataUri(
            tokenId,
            _injectionToken(tokenId, pixels)
        );
    }

    /// @notice NormlForMe NFT animation HTML — reads `(lockedAmount, determinismHash)` from
    ///         the NormlForMe ERC-721 keyed by tokenId.
    /// @dev    Artwork id AND view-window position are both derived from the per-token
    ///         determinismHash, so each token shows a different artwork+position pair
    ///         that is permanent and reproducible from on-chain state alone.
    function animationURIForMe(uint256 tokenId) external view returns (string memory) {
        address nfm = normlForMe;
        if (nfm == address(0)) revert NormlForMeNotSet();
        uint256 amount = INormlForMeReader(nfm).lockedAmount(tokenId);
        if (amount == 0) revert InvalidStakeIndex();
        bytes32 hash = INormlForMeReader(nfm).determinismHash(tokenId);
        // Derive artwork index deterministically from the per-token on-chain hash.
        // This is the same hash committed at mint time (keccak256(prevrandao, tokenId, recipient))
        // so it is permanent, unpredictable at mint time, and reproduces identically on any call.
        uint256 artworkId = uint256(hash) % ARTWORK_COUNT;
        uint256 pixels = amount / 1e18;
        // Position from same hash: keep-out is sized to this token's own pixel count
        // (each ForMe token is its own forever-locked stake).
        (uint16 xBps, uint16 yBps) = _randomPosition(hash, artworkId, pixels);
        return _buildAnimationDataUri(
            artworkId,
            _injectionForMe(artworkId, pixels, hash, xBps, yBps)
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL - PIXEL SOURCES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _liquidPixels(address holder) internal view returns (uint256) {
        address token = normlToken;
        if (token == address(0) || holder == address(0)) return DEFAULT_LIQUID_PIXELS;
        return IERC20(token).balanceOf(holder) / 1e18;
    }

    function _tokenStakedPixels(uint256 tokenId) internal view returns (uint256) {
        address nfu = normlForUs;
        if (nfu == address(0)) return DEFAULT_1OF1_PIXELS;
        return INormlForUsReader(nfu).tokensStakedToToken(tokenId) / 1e18;
    }

    function _stakedPixels(uint256 tokenId) internal view returns (uint256) {
        address nfu = normlForUs;
        if (nfu == address(0)) return 0;
        return INormlForUsReader(nfu).tokensStakedToToken(tokenId) / 1e18;
    }

    /// @dev Starting at `startId`, rotate forward through the artwork set and return
    ///      the first id whose staked-pixel count is strictly below its canvas cap.
    ///      Falls back to `startId` if every artwork is full (degenerate case —
    ///      position picker still clamps gracefully via `_keepOutHalfExtents`).
    function _pickAvailableArtwork(uint256 startId) internal view returns (uint256) {
        for (uint256 i = 0; i < ARTWORK_COUNT; i++) {
            uint256 candidate = (startId + i) % ARTWORK_COUNT;
            uint256 cap = uint256(CANVAS_W[candidate]) * uint256(CANVAS_H[candidate]);
            if (cap == 0) continue;
            if (_stakedPixels(candidate) < cap) return candidate;
        }
        return startId;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               INTERNAL - POSITION ALGORITHM                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint16 internal constant VIEW_MARGIN_BPS = 500; // 5% buffer around the central stake square

    /// @dev Deterministic position picker. Returns view-window center coords in basis points
    ///      (0..10000). Partitions the canvas into a pinwheel of 4 side rectangles around the
    ///      central stake-occupied keep-out box, picks one side uniformly from the seed, then
    ///      picks a uniform point inside it. Each side owns one corner so the four sides have
    ///      pairwise-equal areas (TOP=BOTTOM, LEFT=RIGHT) under rotational symmetry.
    ///
    ///      Pinwheel layout (keep-out centered at 5000,5000 with half-extents hx, hy):
    ///        TOP    : [0 .. 5000+hx]      x [0 .. 5000-hy]        owns top-left corner
    ///        RIGHT  : [5000+hx .. 10000]  x [0 .. 5000+hy]        owns top-right corner
    ///        BOTTOM : [5000-hx .. 10000]  x [5000+hy .. 10000]    owns bottom-right corner
    ///        LEFT   : [0 .. 5000-hx]      x [5000-hy .. 10000]    owns bottom-left corner
    function _randomPosition(
        bytes32 seed,
        uint256 artworkId,
        uint256 stakedPixels
    ) internal view returns (uint16 xBps, uint16 yBps) {
        // Keep-out half-extents in bps (incl. 5% margin), capped to [0, 5000].
        (uint256 hx, uint256 hy) = _keepOutHalfExtents(artworkId, stakedPixels);

        // One seed word fans out into side selector + two coordinate picks.
        uint256 r = uint256(keccak256(abi.encode(seed, "pos")));

        return _pickInSide(
            r & 0x3,            // 0=TOP, 1=RIGHT, 2=BOTTOM, 3=LEFT
            (r >> 64) % 10001,
            (r >> 128) % 10001,
            hx,
            hy
        );
    }

    function _keepOutHalfExtents(uint256 artworkId, uint256 stakedPixels)
        internal
        view
        returns (uint256 hx, uint256 hy)
    {
        uint256 canvasW = CANVAS_W[artworkId];
        uint256 canvasH = CANVAS_H[artworkId];
        uint256 stakeSide = _ceilSqrt(stakedPixels);
        hx = canvasW == 0 ? 0 : (stakeSide * 10000) / (2 * canvasW);
        hy = canvasH == 0 ? 0 : (stakeSide * 10000) / (2 * canvasH);
        hx += VIEW_MARGIN_BPS;
        hy += VIEW_MARGIN_BPS;
        if (hx > 5000) hx = 5000;
        if (hy > 5000) hy = 5000;
    }

    function _pickInSide(
        uint256 side,
        uint256 rx,
        uint256 ry,
        uint256 hx,
        uint256 hy
    ) internal pure returns (uint16 xBps, uint16 yBps) {
        uint256 xLo;
        uint256 xHi;
        uint256 yLo;
        uint256 yHi;
        if (side == 0) {
            xLo = 0;          xHi = 5000 + hx;
            yLo = 0;          yHi = 5000 - hy;
        } else if (side == 1) {
            xLo = 5000 + hx;  xHi = 10000;
            yLo = 0;          yHi = 5000 + hy;
        } else if (side == 2) {
            xLo = 5000 - hx;  xHi = 10000;
            yLo = 5000 + hy;  yHi = 10000;
        } else {
            xLo = 0;          xHi = 5000 - hx;
            yLo = 5000 - hy;  yHi = 10000;
        }
        uint256 spanX = xHi > xLo ? xHi - xLo : 0;
        uint256 spanY = yHi > yLo ? yHi - yLo : 0;
        uint256 x = spanX == 0 ? xLo : xLo + (rx % (spanX + 1));
        uint256 y = spanY == 0 ? yLo : yLo + (ry % (spanY + 1));
        return (uint16(x), uint16(y));
    }

    function _ceilSqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // Integer sqrt (Babylonian).
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        // Round up.
        return y * y < x ? y + 1 : y;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL - HTML BUILDERS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Builds the final `data:text/html;base64,...` blob from a per-artwork asset bundle
    ///      plus a dynamic injection string. See `_padToTriple` for the base64-alignment trick.
    function _buildAnimationDataUri(uint256 artworkId, string memory injection)
        internal
        view
        returns (string memory)
    {
        string memory assetB64 = _readChunkedString(_assetChunks[artworkId]);
        string memory htmlB64  = _readChunkedString(_htmlChunks);
        string memory injB64   = Base64.encode(bytes(_padToTriple(injection)));
        return string.concat(
            "data:text/html;base64,",
            "PHNjcmlwdD4g", // base64("<script> ")
            assetB64,
            injB64,
            htmlB64
        );
    }

    function _injectionLiquid(
        uint256 artworkId,
        uint256 pixels,
        uint16 xBps,
        uint16 yBps
    ) internal pure returns (string memory) {
        return string.concat(
            'window.NORML_DATA={artworkId:', _toString(artworkId),
            ',isLiquid:true',
            ',pixels:', _toString(pixels),
            ',position:[', _toString(xBps), ',', _toString(yBps), ']',
            '};</script>'
        );
    }

    function _injectionToken(uint256 tokenId, uint256 pixels)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            'window.NORML_DATA={artworkId:', _toString(tokenId),
            ',isLiquid:false',
            ',pixels:', _toString(pixels),
            ',position:[5000,5000]',
            '};</script>'
        );
    }

    function _injectionForMe(
        uint256 artworkId,
        uint256 pixels,
        bytes32 determinismHash,
        uint16 xBps,
        uint16 yBps
    )
        internal
        pure
        returns (string memory)
    {
        string memory hashHex = _bytes32ToHex(determinismHash);
        return string.concat(
            'window.NORML_DATA={artworkId:', _toString(artworkId),
            ',isLiquid:false',
            ',pixels:', _toString(pixels),
            ',hash:"0x', hashHex, '"',
            ',position:[', _toString(xBps), ',', _toString(yBps), ']',
            '};',
            // Lock tokenData so the HTML's `var tokenData={}` cannot overwrite it.
            'try{Object.defineProperty(window,"tokenData",{',
                'value:{hash:"0x', hashHex, '"},',
                'writable:false,configurable:false',
            '})}catch(e){}',
            '</script>'
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL - CHUNK IO                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Append 0/1/2 trailing spaces to bring length to a multiple of 3 bytes (base64 alignment).
    function _padToTriple(string memory s) internal pure returns (string memory) {
        uint256 r = bytes(s).length % 3;
        if (r == 0) return s;
        if (r == 1) return string.concat(s, "  ");
        return string.concat(s, " ");
    }

    function _readChunkedString(address[] storage chunks) internal view returns (string memory) {
        return string(_readChunkedData(chunks));
    }

    /// @dev Two-pass extcodecopy concat to avoid quadratic memory growth from `bytes.concat`.
    ///      Chunks are SSTORE2 pointers; the first byte (STOP opcode) is skipped.
    function _readChunkedData(address[] storage chunks) internal view returns (bytes memory result) {
        uint256 len = chunks.length;
        if (len == 0) return result;

        uint256 total;
        for (uint256 i = 0; i < len; i++) {
            address c = chunks[i];
            uint256 sz;
            assembly { sz := extcodesize(c) }
            unchecked { total += sz - 1; }
        }

        result = new bytes(total);
        uint256 offset;
        for (uint256 i = 0; i < len; i++) {
            address c = chunks[i];
            uint256 sz;
            assembly {
                sz := sub(extcodesize(c), 1)
                extcodecopy(c, add(add(result, 0x20), offset), 1, sz)
            }
            unchecked { offset += sz; }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRING UTILS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _bytes32ToHex(bytes32 value) internal pure returns (string memory) {
        bytes memory hexChars = '0123456789abcdef';
        bytes memory result = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            result[i * 2]     = hexChars[uint8(value[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(value[i] & 0x0f)];
        }
        return string(result);
    }
}
