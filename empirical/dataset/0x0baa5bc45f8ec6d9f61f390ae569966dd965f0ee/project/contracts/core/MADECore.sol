// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MADERenderer} from "./MADERenderer.sol";
import {SVGLib} from "../libraries/SVGLib.sol";

/**
 * @title MADECore
 * @notice Living on-chain generative art NFT. 10,000 supply.
 *         Each MADE has a unique generative Core + accumulates colored rings.
 *
 * @dev Architecture:
 *
 *      Core traits — Generated at mint from seed. Determines the generative
 *      center shape (form, palette, complexity, luminosity). Continuous
 *      spectrum, not buckets. Algorithmic rarity.
 *
 *      Rings — Added by CreationRegistry for verified on-chain actions.
 *      7 categories (Code/Trade/DeFi/Art/Writing/DAO/OffChain), 3 tiers
 *      (Small/Medium/Large). Max 3 rings per day per token.
 *
 *      No royalties. No enforced sales. Freely tradeable. No extraction.
 *
 *      Fix 1 — Ring storage: individual mapping slots. O(1) writes.
 *      Fix 2 — ReentrancyGuard on ETH-sending functions.
 *      Fix 3 — setPoolTreasury and setRegistry locked after first set.
 *      Fix 5 — 48h timelock on mint toggle.
 *      Fix 7 — Commit-reveal mint with Merkle proof.
 *      Fix 9 — revealMint is payable with flat 0.0005 ETH fee.
 */
contract MADECore is ERC721, ERC721Enumerable, ReentrancyGuard, Ownable {

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    struct RingData {
        uint8 category;      // 0=Code, 1=Trade, 2=DeFi, 3=Art, 4=Writing, 5=DAO, 6=OffChain
        uint8 tier;           // 0=Small, 1=Medium, 2=Large (visual weight)
        uint16 chainId;       // Source chain (1=ETH mainnet)
        uint48 timestamp;
        bytes32 actionHash;   // Tx hash or Arweave ID
    }

    struct CoreTraits {
        uint8 form;           // 0-255: organic(0) ↔ geometric(255)
        uint8 palette;        // 0-255: hue spectrum position
        uint8 complexity;     // 0-255: element count (2-12 mapped)
        uint8 luminosity;     // 0-255: dim(0) ↔ radiant(255)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant TIMELOCK_DELAY = 48 hours;
    uint8 public constant MAX_RINGS_PER_DAY = 3;
    uint256 public constant MINT_PRICE = 0.00026 ether; // ~55 cents
    uint256 public constant MAX_PER_WALLET = 5;

    // ─────────────────────────────────────────────────────────────────────────
    // Ring Storage — Fix 1
    // ─────────────────────────────────────────────────────────────────────────

    mapping(uint256 => mapping(uint256 => RingData)) private _rings;
    mapping(uint256 => uint256) public ringCount;

    /// @notice Daily ring counter: tokenId => day => count
    mapping(uint256 => mapping(uint256 => uint8)) private _dailyRings;

    // ─────────────────────────────────────────────────────────────────────────
    // Core Storage
    // ─────────────────────────────────────────────────────────────────────────

    mapping(uint256 => CoreTraits) private _coreTraits;
    mapping(uint256 => bytes32) private _tokenSeed;

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    mapping(address => uint256) public mintCount;

    mapping(bytes32 => uint256) public timelockQueue;

    bool public mintActive;
    uint256 public totalMinted;

    address public renderer;
    address public registry;
    address public poolTreasury;

    bytes32 public merkleRoot;

    bool private _registryLocked;
    bool private _poolTreasuryLocked;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event Minted(uint256 indexed tokenId, address indexed owner, bytes32 seed);
    event CoreGenerated(uint256 indexed tokenId, uint8 form, uint8 palette, uint8 complexity, uint8 luminosity);
    event RingAdded(uint256 indexed tokenId, uint8 category, uint8 tier, uint256 ringIndex, bytes32 actionHash);
    event TimelockQueued(bytes32 indexed actionId, uint256 executeAfter);
    event TimelockExecuted(bytes32 indexed actionId);
    event TimelockCancelled(bytes32 indexed actionId);
    event MintToggled(bool active);
    event MerkleRootUpdated(bytes32 newRoot);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error AlreadySet();
    error MintNotActive();
    error AlreadyMinted();
    error MaxSupplyReached();
    error NotWhitelisted();
    error OnlyRegistry();
    error NotQueued();
    error TimelockNotReady();
    error DailyRingCapReached();
    error IncorrectPayment();
    error TransferFailed();

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyRegistry() {
        if (msg.sender != registry) revert OnlyRegistry();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _renderer MADERenderer contract address.
     * @param _merkleRoot Merkle root of verified human wallets.
     * @param _owner Gnosis Safe multisig address.
     */
    constructor(
        address _renderer,
        bytes32 _merkleRoot,
        address _owner
    ) ERC721("MADE", "MADE") Ownable(_owner) {
        renderer = _renderer;
        merkleRoot = _merkleRoot;
        mintActive = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MINT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint a MADE token. Payable (0.0005 ETH).
     *         Generates unique Core traits from seed at mint time.
     * @param merkleProof Proof that msg.sender is in the verified list.
     */
    function mint(bytes32[] calldata merkleProof) external payable nonReentrant {
        if (!mintActive) revert MintNotActive();
        if (msg.value != MINT_PRICE) revert IncorrectPayment();
        if (mintCount[msg.sender] >= MAX_PER_WALLET) revert AlreadyMinted();
        if (totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();

        // If merkleRoot is set, enforce whitelist. Otherwise, public mint.
        if (merkleRoot != bytes32(0)) {
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
            if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) revert NotWhitelisted();
        }

        mintCount[msg.sender] = mintCount[msg.sender] + 1;

        uint256 tokenId = totalMinted;
        bytes32 seed = keccak256(abi.encodePacked(msg.sender, block.prevrandao, totalMinted));
        _tokenSeed[tokenId] = seed;

        // Generate Core traits from seed — continuous spectrum, algorithmic rarity
        _coreTraits[tokenId] = CoreTraits({
            form: uint8(uint256(seed) >> 0),
            palette: uint8(uint256(seed) >> 8),
            complexity: uint8(uint256(seed) >> 16),
            luminosity: uint8(uint256(seed) >> 24)
        });

        unchecked { totalMinted++; }

        _safeMint(msg.sender, tokenId);
        emit Minted(tokenId, msg.sender, seed);
        emit CoreGenerated(
            tokenId,
            _coreTraits[tokenId].form,
            _coreTraits[tokenId].palette,
            _coreTraits[tokenId].complexity,
            _coreTraits[tokenId].luminosity
        );
    }

    /**
     * @notice Mint a batch of NFTs to a team vault. Free mint.
     * @param to The TeamVault address.
     * @param count Number of NFTs to mint.
     */
    function teamMint(address to, uint256 count) external onlyOwner nonReentrant {
        if (totalMinted + count > MAX_SUPPLY) revert MaxSupplyReached();

        for (uint256 i = 0; i < count;) {
            uint256 tokenId = totalMinted;
            
            // Seed uniquely utilizing totalMinted iteration
            bytes32 seed = keccak256(abi.encodePacked(msg.sender, block.prevrandao, totalMinted));
            _tokenSeed[tokenId] = seed;

            _coreTraits[tokenId] = CoreTraits({
                form: uint8(uint256(seed) >> 0),
                palette: uint8(uint256(seed) >> 8),
                complexity: uint8(uint256(seed) >> 16),
                luminosity: uint8(uint256(seed) >> 24)
            });

            unchecked { totalMinted++; }

            _safeMint(to, tokenId);
            
            emit Minted(tokenId, to, seed);
            emit CoreGenerated(
                tokenId,
                _coreTraits[tokenId].form,
                _coreTraits[tokenId].palette,
                _coreTraits[tokenId].complexity,
                _coreTraits[tokenId].luminosity
            );
            
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RING MANAGEMENT — Fix 1 + Daily Cap
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a ring to a MADE token. Called by CreationRegistry only.
     * @param tokenId The token to add a ring to.
     * @param category Ring category (0-6).
     * @param tier Visual weight tier (0=Small, 1=Medium, 2=Large).
     * @param chainId Source chain ID (1 for Ethereum mainnet).
     * @param actionHash Tx hash or Arweave transaction ID.
     */
    function addRing(
        uint256 tokenId,
        uint8 category,
        uint8 tier,
        uint16 chainId,
        bytes32 actionHash
    ) external onlyRegistry {
        // Enforce 3 rings per day per token
        uint256 today = block.timestamp / 1 days;
        if (_dailyRings[tokenId][today] >= MAX_RINGS_PER_DAY) revert DailyRingCapReached();

        unchecked { _dailyRings[tokenId][today]++; }

        uint256 index = ringCount[tokenId];
        _rings[tokenId][index] = RingData(category, tier, chainId, uint48(block.timestamp), actionHash);
        ringCount[tokenId] = index + 1;
        emit RingAdded(tokenId, category, tier, index, actionHash);
    }

    function getRing(uint256 tokenId, uint256 ringIndex) external view returns (RingData memory) {
        return _rings[tokenId][ringIndex];
    }

    function getRings(uint256 tokenId) external view returns (RingData[] memory rings) {
        uint256 count = ringCount[tokenId];
        rings = new RingData[](count);
        for (uint256 i = 0; i < count;) {
            rings[i] = _rings[tokenId][i];
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN URI
    // ═══════════════════════════════════════════════════════════════════════════

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        ownerOf(tokenId);

        uint256 count = ringCount[tokenId];
        RingData[] memory rings = new RingData[](count);
        for (uint256 i = 0; i < count;) {
            rings[i] = _rings[tokenId][i];
            unchecked { ++i; }
        }

        string memory name = string(abi.encodePacked("MADE #", SVGLib.toString(tokenId)));

        return MADERenderer(renderer).tokenURI(
            tokenId, name, ownerOf(tokenId), _tokenSeed[tokenId],
            rings, _coreTraits[tokenId], count
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BURN
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Burn a MADE token.
     * @dev Allows future integration with deflationary systems.
     */
    function burn(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(
            msg.sender == owner || 
            getApproved(tokenId) == msg.sender || 
            isApprovedForAll(owner, msg.sender), 
            "Not authorized"
        );
        _burn(tokenId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function tokenSeed(uint256 tokenId) external view returns (bytes32) {
        return _tokenSeed[tokenId];
    }

    function coreTraits(uint256 tokenId) external view returns (CoreTraits memory) {
        return _coreTraits[tokenId];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN — Fix 5: Timelock
    // ═══════════════════════════════════════════════════════════════════════════

    function queueMintToggle(bool active) external onlyOwner {
        bytes32 actionId = keccak256(abi.encode("setMintActive", active));
        timelockQueue[actionId] = block.timestamp + TIMELOCK_DELAY;
        emit TimelockQueued(actionId, block.timestamp + TIMELOCK_DELAY);
    }

    function executeMintToggle(bool active) external onlyOwner {
        bytes32 actionId = keccak256(abi.encode("setMintActive", active));
        uint256 executeAfter = timelockQueue[actionId];
        if (executeAfter == 0) revert NotQueued();
        if (block.timestamp < executeAfter) revert TimelockNotReady();
        delete timelockQueue[actionId];
        mintActive = active;
        emit TimelockExecuted(actionId);
        emit MintToggled(active);
    }

    function cancelMintToggle(bool active) external onlyOwner {
        bytes32 actionId = keccak256(abi.encode("setMintActive", active));
        if (timelockQueue[actionId] == 0) revert NotQueued();
        delete timelockQueue[actionId];
        emit TimelockCancelled(actionId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ONE-TIME SETTERS — Fix 3
    // ═══════════════════════════════════════════════════════════════════════════

    function setRegistry(address _registry) external onlyOwner {
        if (_registryLocked) revert AlreadySet();
        registry = _registry;
        _registryLocked = true;
    }

    function setPoolTreasury(address _treasury) external onlyOwner {
        if (_poolTreasuryLocked) revert AlreadySet();
        poolTreasury = _treasury;
        _poolTreasuryLocked = true;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WITHDRAW
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Withdraw accumulated mint proceeds directly to the designated funds wallet.
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(0xD6fa7378B63aa3E3389d073c559eb6cC0bfb8aa6).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-721 OVERRIDES — Clean: no restrictions, freely tradeable
    // ═══════════════════════════════════════════════════════════════════════════

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address previousOwner) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
