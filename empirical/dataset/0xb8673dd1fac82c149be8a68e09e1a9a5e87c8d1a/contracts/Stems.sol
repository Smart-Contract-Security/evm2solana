// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * ██████████████████████████████████████████████████████████████
 * ████████████████  STEMS.FM  ██████████████████████████████████
 * ██████████████████████████████████████████████████████████████
 * █  ┌───────────────────────────────────────────────────────┐ █
 * █  │▂▃▅▆▇▆▅▃▂▂▃▅▆▇▆▅▃▂            VOCALS                   │ █
 * █  ├───────────────────────────────────────────────────────┤ █
 * █  │■■■■■■■■  ■■■■■■■■   ■■■■■■■■■■■■■■■   DRUMS           │ █
 * █  ├───────────────────────────────────────────────────────┤ █
 * █  │░░░░░░░░░░░░░░░░░░░░   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒   FX             │ █
 * █  ├───────────────────────────────────────────────────────┤ █
 * █  │▁▂▃▄▅▆▇▆▅▄▃▂▁▁▂▃▄▅▆▇▆▅▄▃▂          GUITAR              │ █
 * █  └───────────────────────────────────────────────────────┘ █
 * ██████████████████████████████████████████████████████████████
 * @title  Stems
 * @author Kyler Simzer
 * @dev BeAWhale
 * @notice A broadcast of stems, songs, and albums.
 */
contract Stems is
    ERC1155,
    ERC1155Burnable,
    ERC1155Supply,
    ERC2981,
    Ownable,
    ReentrancyGuard,
    Pausable
{
    using Strings for uint256;

    // ============ Constants ============
    
    uint8 public constant TYPE_UNREVEALED = 0;
    uint8 public constant TYPE_STEM = 1;
    uint8 public constant TYPE_SONG = 2;
    uint8 public constant TYPE_ALBUM = 3;
    
    uint256 public constant UNREVEALED_TOKEN_ID = 0;
    
    uint256 public constant MAX_MINT_PER_TX = 10;
    uint256 public constant MAX_REVEAL_PER_REQUEST = 20;
    uint256 public constant MAX_FORGE_INPUTS = 100;
    uint256 public constant MINT_DURATION = 14 days;
    uint256 public constant FORGING_DELAY_AFTER_MINT = 1 days;

    uint8 public constant ALBUM_COUNT = 3;

    // ============ Structs ============
    
    struct AlbumConfig {
        string name;
        string upc;
        uint8 totalSongs;
        uint64 releaseDate;
        bool isConfigured;
    }
    
    struct SongConfig {
        string name;
        string isrc;
        uint8 albumId;
        uint8 totalStems;
        uint256 requiredStemMask;
        uint64 releaseDate;
        bool isConfigured;
    }
    
    // ============ State Variables - Mint ============

    uint256 public mintStartTime;
    uint256 public mintEndTime;
    uint256 public totalUnrevealedMinted;
    uint256 public totalRevealed;

    // ============ State Variables - Forging ============

    // Timestamp when forging becomes callable. Auto-set inside `startMint()`
    // to `mintEndTime + FORGING_DELAY_AFTER_MINT` so forging always opens
    // exactly one day after the mint window closes. No admin call required.
    uint256 public forgingStartTime;
    uint256 public totalSongsForged;
    uint256 public totalAlbumsForged;

    // ============ State Variables - Admin Lock ============

    // One-way switch flipped by `lockAdmin()`. After this is true, owner
    // functions for pause/unpause, URI updates, and royalty updates revert.
    // `withdraw()` is permissionless by design and unaffected. Forging is
    // already auto-scheduled from `startMint()`, so there is no
    // owner-controlled forging toggle to lock.
    bool public adminLocked;

    // ============ State Variables - Configuration ============
    
    mapping(uint8 => AlbumConfig) public albumConfigs;
    mapping(uint8 => mapping(uint8 => SongConfig)) public songConfigs;
    mapping(uint8 => string) public stemTypeNames;
    
    // ============ State Variables - Reveal (Equal Probability) ============

    uint256 public totalStemCount; // Total number of stems across all songs
    // O(1) stem lookup: index => packed (albumId << 16 | songId << 8 | stemBit)
    mapping(uint256 => uint256) private stemRegistry;

    // ============ State Variables - Reveal (single global seed, BAYC-style) ============

    // Provenance hash: committed once by the owner before mint starts.
    // Publicly binds the contract to the canonical stem distribution so the
    // owner can't reshuffle traits after the seed is known.
    bytes32 public provenanceHash;
    bool    public provenanceLocked;

    // Reveal seed. Initialized exactly once by `startMint()` from
    // `keccak256(blockhash(block.number-1), provenanceHash, address(this), chainid)`,
    // then rolled forward on every successful reveal:
    //   seed_{t+1} = keccak256(seed_t, word_t)
    // Once seed is set, `seedLocked` is permanently true.
    bytes32 public revealSeed;
    bool    public seedLocked;

    // Global counter of stems that have been revealed. Used as the per-token
    // index when deriving randomness from the global seed.
    uint256 public revealCounter;

    // ============ State Variables - Metadata ============

    string public baseMetadataURI;
    string private _contractURI;

    // ============ Events ============
    
    event Minted(address indexed user, uint256 quantity);
    event Revealed(address indexed user, uint256 indexed newTokenId, uint8 albumId, uint8 songId, uint8 stemBit, uint256 revealIndex);
    event ProvenanceHashSet(bytes32 provenanceHash);
    event SeedLocked(bytes32 revealSeed);
    event Forged(address indexed user, uint256[] burnedTokenIds, uint256[] burnedAmounts, uint256 indexed newTokenId);
    event SongCompleted(address indexed user, uint256 indexed tokenId, uint8 albumId, uint8 songId, string songName);
    event AlbumCompleted(address indexed user, uint256 indexed tokenId, uint8 albumId, string albumName);
    event AlbumConfigured(uint8 indexed albumId, string name, uint8 totalSongs);
    event SongConfigured(uint8 indexed albumId, uint8 indexed songId, string name, uint256 stemMask);
    event StemTypeNameSet(uint8 indexed stemBit, string name);
    event MintStarted(uint256 startTime, uint256 endTime);
    event URIUpdated(string newURI);
    event ContractURIUpdated(string newURI);
    event RoyaltyUpdated(address indexed receiver, uint96 basisPoints);
    event ForgingEnabled(uint256 timestamp);
    event AdminLocked();

    // ============ Errors ============
    
    error MintNotStarted();
    error MintEnded();
    error MintAlreadyStarted();
    error InvalidQuantity();
    error InvalidRecipient();
    error InsufficientBalance();
    error InvalidTokenType();
    error DifferentSongs();
    error DifferentAlbums();
    error SongNotComplete();
    error CannotForgeUnrevealed();
    error CannotMixTokenTypes();
    error ProvenanceNotSet();
    error ProvenanceAlreadyLocked();
    error InvalidProvenanceHash();
    error SeedNotLocked();
    error AlbumAlreadyConfigured();
    error AlbumNotConfigured();
    error SongAlreadyConfigured();
    error SongNotConfigured();
    error InvalidSongConfig();
    error InvalidAlbumId();
    error InvalidSongId();
    error InvalidStemBit();
    error DuplicateStemBit();
    error StemNotInSong();
    error NotAllConfigured();
    error CannotConfigureAfterMint();
    error ArrayLengthMismatch();
    error EmptyArray();
    error RoyaltyTooHigh();
    error ForgingNotEnabled();
    error AdminAlreadyLocked();
    error AdminIsLocked();
    error OwnershipRenounceDisabled();

    // ============ Constructor ============
    
    constructor(
        string memory _baseMetadataURI,
        string memory contractURI_,
        address _royaltyReceiver,
        uint96 _royaltyBasisPoints
    )
        ERC1155(_baseMetadataURI)
        Ownable(msg.sender)
    {
        if (_royaltyReceiver == address(0)) revert InvalidRecipient();
        if (_royaltyBasisPoints > 1000) revert RoyaltyTooHigh();

        baseMetadataURI = _baseMetadataURI;
        _contractURI = contractURI_;

        _setDefaultRoyalty(_royaltyReceiver, _royaltyBasisPoints);
    }

    // ============ Modifiers ============

    modifier beforeMintStarts() {
        if (mintStartTime != 0) revert CannotConfigureAfterMint();
        _;
    }

    modifier whenForgingEnabled() {
        if (forgingStartTime == 0 || block.timestamp < forgingStartTime) revert ForgingNotEnabled();
        _;
    }

    modifier whenAdminUnlocked() {
        if (adminLocked) revert AdminIsLocked();
        _;
    }

    // ============ Token ID Encoding/Decoding ============
    
    /**
     * @notice Encodes token parameters into a single uint256 token ID
     * @param tokenType The type of token (0=UNREVEALED, 1=STEM, 2=SONG, 3=ALBUM)
     * @param albumId The album identifier (0-2)
     * @param songId The song identifier within the album
     * @param bitmap Bitmask of stems (for STEM/SONG) or songs (for ALBUM)
     * @return The encoded token ID
     */
    function encodeTokenId(
        uint8 tokenType,
        uint8 albumId,
        uint8 songId,
        uint256 bitmap
    ) public pure returns (uint256) {
        return (uint256(tokenType) << 248) |
               (uint256(albumId) << 240) |
               (uint256(songId) << 232) |
               (bitmap & ((1 << 232) - 1));
    }
    
    /**
     * @notice Decodes a token ID into its component parts
     * @param tokenId The token ID to decode
     * @return tokenType The type of token
     * @return albumId The album identifier
     * @return songId The song identifier
     * @return bitmap The stem or song bitmask
     */
    function decodeTokenId(uint256 tokenId) public pure returns (
        uint8 tokenType,
        uint8 albumId,
        uint8 songId,
        uint256 bitmap
    ) {
        tokenType = uint8(tokenId >> 248);
        albumId = uint8((tokenId >> 240) & 0xFF);
        songId = uint8((tokenId >> 232) & 0xFF);
        bitmap = tokenId & ((1 << 232) - 1);
    }

    // ============ Minting ============
    
    /**
     * @notice Mint unrevealed stem tokens. Free mint, capped at MAX_MINT_PER_TX
     *         per call. Caller receives exactly `quantity` tokens — no bonus.
     * @param quantity Number of tokens to mint
     */
    function mint(uint256 quantity) external nonReentrant whenNotPaused {
        if (mintStartTime == 0 || block.timestamp < mintStartTime) revert MintNotStarted();
        if (block.timestamp > mintEndTime) revert MintEnded();
        if (quantity == 0 || quantity > MAX_MINT_PER_TX) revert InvalidQuantity();

        _mint(msg.sender, UNREVEALED_TOKEN_ID, quantity, "");
        totalUnrevealedMinted += quantity;

        emit Minted(msg.sender, quantity);
    }


    // ============ Reveal ============
    
    /**
     * @notice Reveal `quantity` of the caller's unrevealed tokens.
     * @dev Burns N unrevealed tokens and mints N stem tokens whose traits
     *      are derived from `keccak256(msg.sender, revealSeed, revealCounter)`.
     *      After every successful reveal the global `revealSeed` is replaced
     *      with `keccak256(revealSeed, word)` so the next caller draws from a
     *      different seed state. The address binding plus the rolling seed
     *      mean a sniper can't precompute a flat "slot N = stem X" sequence:
     *      what slot N produces depends on which addresses revealed before
     *      and in what order.
     * @param quantity Number of tokens to reveal (1 .. MAX_REVEAL_PER_REQUEST)
     */
    function reveal(uint256 quantity) external nonReentrant whenNotPaused {
        if (!seedLocked) revert SeedNotLocked();
        if (quantity == 0 || quantity > MAX_REVEAL_PER_REQUEST) revert InvalidQuantity();
        if (balanceOf(msg.sender, UNREVEALED_TOKEN_ID) < quantity) revert InsufficientBalance();

        _burn(msg.sender, UNREVEALED_TOKEN_ID, quantity);

        bytes32 seed = revealSeed;
        for (uint256 i = 0; i < quantity; i++) {
            uint256 idx;
            unchecked { idx = revealCounter++; }

            uint256 word = uint256(keccak256(abi.encodePacked(msg.sender, seed, idx)));
            (uint8 albumId, uint8 songId, uint8 stemBit) = _selectRandomStem(word);

            uint256 newTokenId = encodeTokenId(TYPE_STEM, albumId, songId, 1 << stemBit);
            _mint(msg.sender, newTokenId, 1, "");
            totalRevealed++;

            // Roll the seed forward so the next reveal — same caller or not —
            // draws from a different state. Anyone who wants to predict their
            // own future outcome must also predict who reveals between now and
            // then.
            seed = keccak256(abi.encodePacked(seed, word));

            emit Revealed(msg.sender, newTokenId, albumId, songId, stemBit, idx);
        }
        revealSeed = seed;
    }

    /**
     * @notice Select a random stem with equal probability using O(1) registry lookup.
     * @param randomWord Random number derived from the global seed
     * @return albumId The selected album
     * @return songId The selected song
     * @return stemBit The selected stem bit position
     * @dev Uses pre-computed stemRegistry populated during configureSong()
     */
    function _selectRandomStem(uint256 randomWord) internal view returns (
        uint8 albumId,
        uint8 songId,
        uint8 stemBit
    ) {
        uint256 index = randomWord % totalStemCount;
        uint256 packed = stemRegistry[index];
        return (uint8(packed >> 16), uint8(packed >> 8), uint8(packed));
    }

    // ============ Forging ============

    /**
     * @notice Forge multiple tokens into a combined token
     * @dev Stems can be forged into partial or complete songs (TYPE_STEM or TYPE_SONG)
     * @dev Songs can be forged into partial or complete albums (TYPE_ALBUM)
     * @dev Albums can be combined to merge song collections
     * @param tokenIds Array of token IDs to forge
     * @param amounts Array of amounts for each token ID
     * @return newTokenId The newly created token ID
     */
    function forge(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused whenForgingEnabled returns (uint256 newTokenId) {
        if (tokenIds.length != amounts.length) revert ArrayLengthMismatch();
        if (tokenIds.length == 0) revert EmptyArray();
        if (tokenIds.length > MAX_FORGE_INPUTS) revert InvalidQuantity();
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (amounts[i] != 1) revert InvalidQuantity();
            if (balanceOf(msg.sender, tokenIds[i]) == 0) revert InsufficientBalance();
        }
        
        (uint8 firstType, uint8 album, uint8 song, ) = decodeTokenId(tokenIds[0]);
        
        if (firstType == TYPE_UNREVEALED) revert CannotForgeUnrevealed();
        
        if (firstType == TYPE_STEM) {
            newTokenId = _forgeStems(tokenIds, amounts, album, song);
        } else if (firstType == TYPE_SONG || firstType == TYPE_ALBUM) {
            newTokenId = _forgeSongsOrAlbums(tokenIds, amounts, album);
        } else {
            revert InvalidTokenType();
        }
        
        _burnBatch(msg.sender, tokenIds, amounts);
        _mint(msg.sender, newTokenId, 1, "");
        
        emit Forged(msg.sender, tokenIds, amounts, newTokenId);
        
        return newTokenId;
    }
    
    /**
     * @notice Internal function to forge stems into a combined stem or complete song
     * @dev Creates TYPE_STEM token for partial stems, TYPE_SONG for complete stems
     */
    function _forgeStems(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint8 targetAlbum,
        uint8 targetSong
    ) internal returns (uint256) {
        uint256 combinedBitmap = 0;
        SongConfig memory songConfig = songConfigs[targetAlbum][targetSong];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint8 tType, uint8 tAlbum, uint8 tSong, uint256 tBitmap) = decodeTokenId(tokenIds[i]);

            if (tType != TYPE_STEM) revert CannotMixTokenTypes();
            if (tAlbum != targetAlbum) revert DifferentAlbums();
            if (tSong != targetSong) revert DifferentSongs();

            // SECURITY FIX (C-5): Verify all bits in tBitmap are valid for this song
            // Prevents forging tokens with invalid stem bits
            if ((tBitmap & ~songConfig.requiredStemMask) != 0) revert StemNotInSong();

            // SECURITY FIX (M-4): Check if this token adds any new bits
            // Prevents wasting gas on duplicate stems
            if ((combinedBitmap & tBitmap) == tBitmap) revert DuplicateStemBit();

            combinedBitmap |= tBitmap;
        }
        bool isComplete = (combinedBitmap == songConfig.requiredStemMask);
        
        uint8 resultType = isComplete ? TYPE_SONG : TYPE_STEM;
        uint256 newTokenId = encodeTokenId(resultType, targetAlbum, targetSong, combinedBitmap);
        
        if (isComplete) {
            totalSongsForged++;
            emit SongCompleted(msg.sender, newTokenId, targetAlbum, targetSong, songConfig.name);
        }

        return newTokenId;
    }
    
    /**
     * @notice Internal function to forge songs/albums into an album (partial or complete)
     */
    function _forgeSongsOrAlbums(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint8 targetAlbum
    ) internal returns (uint256) {
        uint256 songBitmap = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint8 tType, uint8 tAlbum, uint8 tSong, uint256 tBitmap) = decodeTokenId(tokenIds[i]);

            if (tAlbum != targetAlbum) revert DifferentAlbums();

            if (tType == TYPE_STEM) {
                revert CannotMixTokenTypes();
            } else if (tType == TYPE_SONG) {
                SongConfig memory songConfig = songConfigs[tAlbum][tSong];
                if (tBitmap != songConfig.requiredStemMask) revert SongNotComplete();
                songBitmap |= (1 << tSong);
            } else if (tType == TYPE_ALBUM) {
                songBitmap |= tBitmap;
            } else {
                revert InvalidTokenType();
            }
        }

        // Create album token (partial or complete)
        AlbumConfig memory albumConfig = albumConfigs[targetAlbum];
        uint256 newTokenId = encodeTokenId(TYPE_ALBUM, targetAlbum, 0, songBitmap);

        // Only emit AlbumCompleted if all songs are present
        if (_countBits(songBitmap) == albumConfig.totalSongs) {
            totalAlbumsForged++;
            emit AlbumCompleted(msg.sender, newTokenId, targetAlbum, albumConfig.name);
        }

        return newTokenId;
    }

    // ============ View Functions ============

    /**
     * @notice Get album configuration
     */
    function getAlbumConfig(uint8 albumId) external view returns (AlbumConfig memory) {
        if (!albumConfigs[albumId].isConfigured) revert AlbumNotConfigured();
        return albumConfigs[albumId];
    }
    
    /**
     * @notice Get song configuration
     */
    function getSongConfig(uint8 albumId, uint8 songId) external view returns (SongConfig memory) {
        if (!songConfigs[albumId][songId].isConfigured) revert SongNotConfigured();
        return songConfigs[albumId][songId];
    }
    
    // ============ Configuration Functions ============
    
    /**
     * @notice Configure an album
     */
    function configureAlbum(
        uint8 albumId,
        string calldata name,
        string calldata upc,
        uint8 totalSongs,
        uint64 releaseDate
    ) external onlyOwner beforeMintStarts {
        if (albumId >= ALBUM_COUNT) revert InvalidAlbumId();
        if (albumConfigs[albumId].isConfigured) revert AlbumAlreadyConfigured();
        if (totalSongs == 0) revert InvalidQuantity();
        
        albumConfigs[albumId] = AlbumConfig({
            name: name,
            upc: upc,
            totalSongs: totalSongs,
            releaseDate: releaseDate,
            isConfigured: true
        });
        
        emit AlbumConfigured(albumId, name, totalSongs);
    }
    
    /**
     * @notice Configure a song
     */
    function configureSong(
        uint8 albumId,
        uint8 songId,
        string calldata name,
        string calldata isrc,
        uint8[] calldata stemBits,
        uint64 releaseDate
    ) external onlyOwner beforeMintStarts {
        if (!albumConfigs[albumId].isConfigured) revert AlbumNotConfigured();
        if (songId >= albumConfigs[albumId].totalSongs) revert InvalidSongId();
        if (songConfigs[albumId][songId].isConfigured) revert SongAlreadyConfigured();
        if (stemBits.length == 0) revert EmptyArray();
        
        uint256 stemMask = 0;
        for (uint256 i = 0; i < stemBits.length; i++) {
            if (stemBits[i] >= 232) revert InvalidStemBit();

            // Check if this bit is already set (duplicate detection)
            if ((stemMask & (1 << stemBits[i])) != 0) revert DuplicateStemBit();

            stemMask |= (1 << stemBits[i]);
        }

        // SECURITY FIX (H-3): Ensure stemMask is not zero (prevents unforge-able songs)
        if (stemMask == 0) revert InvalidSongConfig();

        songConfigs[albumId][songId] = SongConfig({
            name: name,
            isrc: isrc,
            albumId: albumId,
            totalStems: uint8(stemBits.length),
            requiredStemMask: stemMask,
            releaseDate: releaseDate,
            isConfigured: true
        });

        // Populate O(1) stem lookup registry
        uint256 regIdx = totalStemCount;
        for (uint256 i = 0; i < stemBits.length; i++) {
            stemRegistry[regIdx] = (uint256(albumId) << 16) | (uint256(songId) << 8) | uint256(stemBits[i]);
            regIdx++;
        }
        totalStemCount = regIdx;

        emit SongConfigured(albumId, songId, name, stemMask);
    }
    
    /**
     * @notice Batch configure albums
     */
    function configureAlbumsBatch(
        uint8[] calldata albumIds,
        string[] calldata names,
        string[] calldata upcs,
        uint8[] calldata totalSongsArr,
        uint64[] calldata releaseDates
    ) external onlyOwner beforeMintStarts {
        if (albumIds.length != names.length || albumIds.length != upcs.length ||
            albumIds.length != totalSongsArr.length || albumIds.length != releaseDates.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < albumIds.length; i++) {
            uint8 albumId = albumIds[i];
            if (albumId >= ALBUM_COUNT) revert InvalidAlbumId();
            if (albumConfigs[albumId].isConfigured) revert AlbumAlreadyConfigured();
            if (totalSongsArr[i] == 0) revert InvalidQuantity();

            albumConfigs[albumId] = AlbumConfig({
                name: names[i],
                upc: upcs[i],
                totalSongs: totalSongsArr[i],
                releaseDate: releaseDates[i],
                isConfigured: true
            });

            emit AlbumConfigured(albumId, names[i], totalSongsArr[i]);
        }
    }

    struct SongInput {
        uint8 albumId;
        uint8 songId;
        string name;
        string isrc;
        uint8[] stemBits;
        uint64 releaseDate;
    }

    /**
     * @notice Batch configure songs
     */
    function configureSongsBatch(SongInput[] calldata songs) external onlyOwner beforeMintStarts {
        for (uint256 i = 0; i < songs.length; i++) {
            SongInput calldata s = songs[i];

            if (!albumConfigs[s.albumId].isConfigured) revert AlbumNotConfigured();
            if (s.songId >= albumConfigs[s.albumId].totalSongs) revert InvalidSongId();
            if (songConfigs[s.albumId][s.songId].isConfigured) revert SongAlreadyConfigured();
            if (s.stemBits.length == 0) revert EmptyArray();

            uint256 stemMask = 0;
            for (uint256 j = 0; j < s.stemBits.length; j++) {
                if (s.stemBits[j] >= 232) revert InvalidStemBit();
                if ((stemMask & (1 << s.stemBits[j])) != 0) revert DuplicateStemBit();
                stemMask |= (1 << s.stemBits[j]);
            }

            if (stemMask == 0) revert InvalidSongConfig();

            songConfigs[s.albumId][s.songId] = SongConfig({
                name: s.name,
                isrc: s.isrc,
                albumId: s.albumId,
                totalStems: uint8(s.stemBits.length),
                requiredStemMask: stemMask,
                releaseDate: s.releaseDate,
                isConfigured: true
            });

            uint256 regIdx = totalStemCount;
            for (uint256 j = 0; j < s.stemBits.length; j++) {
                stemRegistry[regIdx] = (uint256(s.albumId) << 16) | (uint256(s.songId) << 8) | uint256(s.stemBits[j]);
                regIdx++;
            }
            totalStemCount = regIdx;

            emit SongConfigured(s.albumId, s.songId, s.name, stemMask);
        }
    }

    /**
     * @notice Configure stem type names
     */
    function configureStemTypeName(uint8 stemBit, string calldata name) external onlyOwner beforeMintStarts {
        if (stemBit >= 232) revert InvalidStemBit();
        stemTypeNames[stemBit] = name;
        emit StemTypeNameSet(stemBit, name);
    }
    
    /**
     * @notice Batch configure stem type names
     */
    function configureStemTypeNames(
        uint8[] calldata stemBits,
        string[] calldata names
    ) external onlyOwner beforeMintStarts {
        if (stemBits.length != names.length) revert ArrayLengthMismatch();
        
        for (uint256 i = 0; i < stemBits.length; i++) {
            if (stemBits[i] >= 232) revert InvalidStemBit();
            stemTypeNames[stemBits[i]] = names[i];
            emit StemTypeNameSet(stemBits[i], names[i]);
        }
    }

    /**
     * @notice Schedule the mint window. Locks the reveal seed atomically.
     * @dev Mint is free; no price parameter.
     * @param daysDelay Number of days from now until minting opens. Pass 0
     *                  for "open immediately". The seed is anchored at this
     *                  call regardless — it does not wait for the delay.
     */
    function startMint(uint256 daysDelay) external onlyOwner {
        if (mintStartTime != 0) revert MintAlreadyStarted();
        if (!provenanceLocked) revert ProvenanceNotSet();
        if (!_allSongsConfigured()) revert NotAllConfigured();

        _validateStemRegistry();

        // Anchor the reveal seed to the most recent committed blockhash
        // visible to the contract, mixed with the previously committed
        // provenance hash plus contract identity. From here on, every reveal
        // rolls the seed forward.
        revealSeed = keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),
                provenanceHash,
                address(this),
                block.chainid
            )
        );
        seedLocked = true;
        emit SeedLocked(revealSeed);

        mintStartTime = block.timestamp + daysDelay * 1 days;
        mintEndTime = mintStartTime + MINT_DURATION;

        // Forging unlocks automatically FORGING_DELAY_AFTER_MINT after the
        // mint window closes. No separate admin call required.
        forgingStartTime = mintEndTime + FORGING_DELAY_AFTER_MINT;

        emit MintStarted(mintStartTime, mintEndTime);
        emit ForgingEnabled(forgingStartTime);
    }
    
    /**
     * @notice Check if all albums and songs are configured
     */
    function _allSongsConfigured() internal view returns (bool) {
        for (uint8 a = 0; a < ALBUM_COUNT; a++) {
            if (!albumConfigs[a].isConfigured) return false;
            for (uint8 s = 0; s < albumConfigs[a].totalSongs; s++) {
                if (!songConfigs[a][s].isConfigured) return false;
            }
        }
        return true;
    }

    /**
     * @notice Validate that stem registry was populated during configuration
     * @dev totalStemCount is now incremented during configureSong()
     */
    function _validateStemRegistry() internal view {
        if (totalStemCount == 0) revert NotAllConfigured();
    }

    // ============ Admin Functions ============

    /**
     * @notice Boolean view: is forging callable right now?
     * @dev Forging unlocks `FORGING_DELAY_AFTER_MINT` after `mintEndTime`,
     *      which is set inside `startMint()`. No separate admin call exists.
     */
    function forgingEnabled() external view returns (bool) {
        return forgingStartTime != 0 && block.timestamp >= forgingStartTime;
    }

    /**
     * @notice Seconds remaining until the mint window opens.
     * @return 0 if mint isn't scheduled yet, or if it's already open / ended.
     */
    function getTimeUntilMintStarts() external view returns (uint256) {
        if (mintStartTime == 0) return 0;
        if (block.timestamp >= mintStartTime) return 0;
        return mintStartTime - block.timestamp;
    }

    /**
     * @notice Seconds remaining until forging unlocks.
     * @return 0 if forging isn't scheduled yet, or if it's already enabled.
     */
    function getTimeUntilForgingEnabled() external view returns (uint256) {
        if (forgingStartTime == 0) return 0;
        if (block.timestamp >= forgingStartTime) return 0;
        return forgingStartTime - block.timestamp;
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner whenAdminUnlocked {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner whenAdminUnlocked {
        _unpause();
    }

    /**
     * @notice Permanently disable owner control surface. One-way: cannot be undone.
     * @dev After this call, `pause`, `unpause`, `setBaseMetadataURI`,
     *      `setContractURI`, and `setRoyaltyInfo` all revert with
     *      `AdminIsLocked`. `renounceOwnership` is permanently disabled
     *      regardless. `transferOwnership` keeps working in case the owner
     *      wants to rotate the wallet (e.g., to a multisig) before locking.
     *      Forging is auto-scheduled at `startMint()` time and is not gated
     *      by `lockAdmin`.
     */
    function lockAdmin() external onlyOwner {
        if (adminLocked) revert AdminAlreadyLocked();
        adminLocked = true;
        emit AdminLocked();
    }

    /**
     * @notice Disabled. The contract permanently retains an owner so that
     *         `transferOwnership` is always available for wallet rotation.
     */
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipRenounceDisabled();
    }

    /**
     * @notice Update base metadata URI
     */
    function setBaseMetadataURI(string calldata newURI) external onlyOwner whenAdminUnlocked {
        baseMetadataURI = newURI;
        emit URIUpdated(newURI);
    }

    /**
     * @notice Update contract URI
     */
    function setContractURI(string calldata newURI) external onlyOwner whenAdminUnlocked {
        _contractURI = newURI;
        emit ContractURIUpdated(newURI);
    }

    /**
     * @notice Update royalty configuration
     */
    function setRoyaltyInfo(address receiver, uint96 basisPoints) external onlyOwner whenAdminUnlocked {
        if (receiver == address(0)) revert InvalidRecipient();
        if (basisPoints > 1000) revert RoyaltyTooHigh();
        
        _setDefaultRoyalty(receiver, basisPoints);
        
        emit RoyaltyUpdated(receiver, basisPoints);
    }
    
    /**
     * @notice Set the provenance hash. One-shot: can only be set once, before
     *         the first reveal is requested.
     * @dev The provenance hash should be computed off-chain as a commitment to
     *      the canonical stem ordering / distribution. Publishing it before any
     *      reveal lets collectors later verify that traits were not reshuffled.
     * @param hash The provenance hash (non-zero)
     */
    function setProvenanceHash(bytes32 hash) external onlyOwner {
        if (provenanceLocked) revert ProvenanceAlreadyLocked();
        if (hash == bytes32(0)) revert InvalidProvenanceHash();
        provenanceHash = hash;
        provenanceLocked = true;
        emit ProvenanceHashSet(hash);
    }

    // ============ URI Functions ============
    
    /**
     * @notice Get token metadata URI
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        if (tokenId == UNREVEALED_TOKEN_ID) {
            return string(abi.encodePacked(baseMetadataURI, "/unrevealed.json"));
        }
        
        return string(abi.encodePacked(baseMetadataURI, "/", tokenId.toString(), ".json"));
    }
    
    /**
     * @notice Get contract-level metadata URI
     */
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    // ============ Utility Functions ============

    /**
     * @notice Count set bits in a bitmap using Kernighan's algorithm
     * @dev Only loops once per SET bit (not once per bit position)
     * @dev For a bitmap with N set bits, runs in O(N) instead of O(256)
     * @dev Example: bitmap with 10 bits set → 10 iterations (not 256)
     * @param bitmap The bitmap to count set bits in
     * @return count The number of set bits
     */
    function _countBits(uint256 bitmap) internal pure returns (uint256 count) {
        unchecked {
            while (bitmap != 0) {
                bitmap &= bitmap - 1; // Clears the rightmost set bit
                ++count;
            }
        }
    }

    // ============ Required Overrides ============
    
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
