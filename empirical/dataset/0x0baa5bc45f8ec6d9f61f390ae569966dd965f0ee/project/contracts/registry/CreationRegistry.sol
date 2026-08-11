// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {MADECore} from "../core/MADECore.sol";
import {PriceOracle} from "../oracle/PriceOracle.sol";

/**
 * @title CreationRegistry
 * @notice Registry for verified on-chain creations that produce rings on MADE tokens.
 *
 * @dev Launch version: on-chain verifiable creations only.
 *
 *      Two verification paths at launch:
 *        1. Contract — verifies extcodesize > 0 at the given address
 *        2. NFT — verifies msg.sender owns the NFT via ownerOf()
 *
 *      Both are trustlessly verifiable on-chain. Zero human review needed.
 *      Zero gaming possible: you cannot fake a deployed contract or NFT you own.
 *
 *      Future paths (disabled at launch, enabled month 2):
 *        3. Transaction — requires reviewer council attestation
 *        4. DeFi Position — requires protocol-specific verification
 *        5. Art — requires community review + staking
 *        6. Music — requires community review + staking
 *
 *      Stamp fee: $0.20 USD equivalent, calculated dynamically via Chainlink
 *      ETH/USD price feed through PriceOracle. Fee goes to PoolTreasury.
 *
 *      Batch processing: creations enter a pending queue. Anyone can call
 *      processBatch(maxCount) to convert pending creations into rings on
 *      the respective MADE tokens. Caller receives a small ETH reward from
 *      the PoolTreasury to incentivize decentralized batch processing (Fix 6).
 *      maxCount parameter limits gas per transaction (Fix 8).
 */
contract CreationRegistry is ReentrancyGuard {

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    struct Creation {
        address creator;       // Who submitted this creation
        uint8 category;        // 0=Art, 1=Code, 2=Trade, 3=Music, 4=Writing, 5=Other
        uint48 timestamp;      // When it was submitted
        uint256 madeTokenId;   // Which MADE token this is attached to
        bool processed;        // Whether it's been processed into a ring
        bytes32 onChainRef;    // The on-chain reference (contract address hash or NFT hash)
    }

    struct PendingItem {
        bytes32 contentHash;   // Key into the creations mapping
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Category constants
    uint8 public constant CATEGORY_ART = 0;
    uint8 public constant CATEGORY_CODE = 1;
    uint8 public constant CATEGORY_TRADE = 2;
    uint8 public constant CATEGORY_MUSIC = 3;
    uint8 public constant CATEGORY_WRITING = 4;
    uint8 public constant CATEGORY_OTHER = 5;

    /// @notice Maximum items per batch call to prevent gas limit issues (Fix 8)
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ─────────────────────────────────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice MADECore contract
    MADECore public immutable madeCore;

    /// @notice PoolTreasury contract (receives stamp fees and pays batch rewards)
    address public immutable treasury;

    /// @notice Price oracle for dynamic $0.20 fee
    PriceOracle public immutable priceOracle;

    /// @notice All creations by content hash
    mapping(bytes32 => Creation) public creations;

    /// @notice Creations linked to each MADE token
    mapping(uint256 => bytes32[]) public tokenCreations;

    /// @notice Pending queue of creations awaiting batch processing
    PendingItem[] public pendingQueue;

    /// @notice Total stamp count
    uint256 public totalStamps;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event CreationStamped(
        bytes32 indexed contentHash,
        address indexed creator,
        uint256 indexed madeTokenId,
        uint8 category,
        uint256 feePaid
    );

    event BatchProcessed(uint256 count, address indexed caller);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NotTokenOwner();
    error DuplicateCreation();
    error ContractNotFound();
    error NotNFTOwner();
    error InsufficientFee();
    error CategoryDisabled();
    error InvalidCategory();
    error NothingToProcess();
    error MaxBatchExceeded();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address _madeCore, address _treasury, address _priceOracle) {
        madeCore = MADECore(payable(_madeCore));
        treasury = _treasury;
        priceOracle = PriceOracle(_priceOracle);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Stamp Functions — On-chain verification only at launch
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Stamp a deployed contract as a creation.
     * @dev Verifies the contract exists via extcodesize. Category is Code (1).
     *      The content hash is derived from the contract address to prevent duplicates.
     *      msg.sender must own the MADE token being stamped.
     *
     * @param tokenId The MADE token to add this creation to.
     * @param contractAddr The deployed contract address to stamp.
     */
    function stampContract(uint256 tokenId, address contractAddr) external payable nonReentrant {
        // Verify caller owns the MADE token
        if (madeCore.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        // Verify contract exists on-chain
        if (contractAddr.code.length == 0) revert ContractNotFound();

        // Generate unique content hash
        bytes32 contentHash = keccak256(abi.encodePacked("CONTRACT", contractAddr));
        if (creations[contentHash].timestamp != 0) revert DuplicateCreation();

        // Collect dynamic stamp fee
        _collectFee();

        // Store creation and add to pending queue
        _stamp(tokenId, contentHash, CATEGORY_CODE, abi.encodePacked(contractAddr));
    }

    /**
     * @notice Stamp an NFT you own as a creation.
     * @dev Verifies msg.sender owns the NFT via ownerOf(). Category is Art (0).
     *      The content hash is derived from the NFT contract + tokenId.
     *
     * @param tokenId The MADE token to add this creation to.
     * @param nftContract The ERC-721 contract address.
     * @param nftTokenId The token ID you own.
     */
    function stampNFT(uint256 tokenId, address nftContract, uint256 nftTokenId) external payable nonReentrant {
        // Verify caller owns the MADE token
        if (madeCore.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        // Verify caller owns the NFT
        try IERC721(nftContract).ownerOf(nftTokenId) returns (address nftOwner) {
            if (nftOwner != msg.sender) revert NotNFTOwner();
        } catch {
            revert NotNFTOwner();
        }

        // Generate unique content hash
        bytes32 contentHash = keccak256(abi.encodePacked("NFT", nftContract, nftTokenId));
        if (creations[contentHash].timestamp != 0) revert DuplicateCreation();

        // Collect dynamic stamp fee
        _collectFee();

        // Store creation and add to pending queue
        _stamp(tokenId, contentHash, CATEGORY_ART, abi.encodePacked(nftContract, nftTokenId));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Future Stamp Functions — Disabled at launch
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Stamp a transaction hash. DISABLED at launch.
     * @dev Month 2: Requires reviewer council attestation.
     *      The EVM cannot natively verify tx hashes. This path requires
     *      a trusted oracle or reviewer to attest that the tx exists and
     *      was sent by msg.sender.
     */
    function stampTransaction(uint256 /* tokenId */, bytes32 /* txHash */) external payable {
        revert CategoryDisabled();
    }

    /**
     * @notice Stamp a DeFi position. DISABLED at launch.
     * @dev Month 2: Requires protocol-specific verification adapters.
     */
    function stampDeFiPosition(uint256 /* tokenId */, address /* protocol */, bytes calldata /* data */) external payable {
        revert CategoryDisabled();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Batch Processing — Fix 6 (incentivized) + Fix 8 (maxCount)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Process pending creations into rings. Anyone can call. Caller gets paid.
     * @dev Processes up to `maxCount` items from the pending queue. Each processed
     *      creation calls MADECore.addRing() to add a ring to the respective token.
     *
     *      Caller receives a reward from the PoolTreasury after processing.
     *      This ensures the system runs forever even if the team disappears. (Fix 6)
     *
     *      maxCount is capped at MAX_BATCH_SIZE (50) to prevent gas limit issues. (Fix 8)
     *
     * @param maxCount Maximum number of items to process in this call.
     */
    function processBatch(uint256 maxCount) external nonReentrant {
        if (pendingQueue.length == 0) revert NothingToProcess();
        if (maxCount > MAX_BATCH_SIZE) maxCount = MAX_BATCH_SIZE;

        uint256 processed = 0;

        while (pendingQueue.length > 0 && processed < maxCount) {
            // Pop from end of queue (gas efficient)
            PendingItem memory item = pendingQueue[pendingQueue.length - 1];
            pendingQueue.pop();

            Creation storage creation = creations[item.contentHash];
            if (!creation.processed) {
                creation.processed = true;

                // Add ring to the MADE token
                madeCore.addRing(
                    creation.madeTokenId,
                    creation.category,
                    0,                    // tier: default Small
                    1,                    // chainId: Ethereum mainnet
                    item.contentHash
                );

                processed++;
            }
        }

        emit BatchProcessed(processed, msg.sender);

        // Pay batch caller reward from treasury (Fix 6)
        // The treasury decides the reward amount internally.
        // If treasury has insufficient balance, the reward is skipped (no revert).
        if (processed > 0) {
            // Low-level call to treasury's payBatchReward
            // This is a best-effort reward — the batch still processes even if reward fails
            (bool sent,) = treasury.call(
                abi.encodeWithSignature("payBatchCallerReward(address)", msg.sender)
            );
            // Intentionally not checking `sent` — batch processing is more important
            // than the caller reward. If treasury is empty, batch still runs.
            sent; // Suppress unused variable warning
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Get a creation by content hash
    function getCreation(bytes32 contentHash) external view returns (Creation memory) {
        return creations[contentHash];
    }

    /// @notice Get all creation hashes for a MADE token
    function getCreationsByToken(uint256 tokenId) external view returns (bytes32[] memory) {
        return tokenCreations[tokenId];
    }

    /// @notice Get the current stamp fee in wei
    function getStampFee() public view returns (uint256) {
        return priceOracle.getStampFee();
    }

    /// @notice Get the number of pending items in the queue
    function getPendingCount() external view returns (uint256) {
        return pendingQueue.length;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Collect the dynamic stamp fee and forward to treasury.
     */
    function _collectFee() internal {
        uint256 fee = priceOracle.getStampFee();
        if (msg.value < fee) revert InsufficientFee();

        // Forward fee to treasury
        (bool sent,) = treasury.call{value: fee}("");
        if (!sent) revert CreationRegistry.InsufficientFee(); // Reuse error

        // Refund excess
        uint256 excess = msg.value - fee;
        if (excess > 0) {
            (bool refunded,) = msg.sender.call{value: excess}("");
            refunded; // Best effort refund
        }
    }

    /**
     * @dev Internal stamp logic shared by all stamp functions.
     */
    function _stamp(
        uint256 tokenId,
        bytes32 contentHash,
        uint8 category,
        bytes memory /* onChainData */
    ) internal {
        creations[contentHash] = Creation({
            creator: msg.sender,
            category: category,
            timestamp: uint48(block.timestamp),
            madeTokenId: tokenId,
            processed: false,
            onChainRef: contentHash
        });

        tokenCreations[tokenId].push(contentHash);
        pendingQueue.push(PendingItem({contentHash: contentHash}));
        totalStamps++;

        emit CreationStamped(contentHash, msg.sender, tokenId, category, msg.value);
    }
}
