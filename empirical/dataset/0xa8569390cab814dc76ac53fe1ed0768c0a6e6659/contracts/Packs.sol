// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDMeth} from "../interfaces/IDMeth.sol";

/*
 * IMPORTANT 
 *
 * The Packs contract must hold both burn AND mint authorization on the dMETH
 * token. If your dMETH does not expose mint, see the comment on
 * refundExpiredRequest() for an alternate credit-based refund path.
 */

interface IMinerNFTMint {
    function mintMinerNFT(
        address to,
        uint32 minerId,
        uint8 minerIndex,
        uint32 hashrate,
        uint32 powerConsumption
    ) external returns (uint256);
}

interface IMiningSystemMint {
    function minerTemplates(uint256)
        external
        view
        returns (uint32 hashrate, uint32 energy, uint256 cost, bool inProduction);
    function reserveMinerId() external returns (uint32);
    function uniqueMinerCount() external view returns (uint8);
}

/**
 * @title Packs (commit-reveal)
 * @notice On-chain pack opener for Mining ETH using an operator-assisted
 * two-party commit-reveal randomness scheme.
 *
 * RANDOMNESS DESIGN
 * -----------------
 * The operator (an off-chain service controlled by the project) pre-commits
 * a queue of secret-hash commitments on-chain via {addCommitments}. Each
 * commitment is `keccak256(abi.encode(secret))` for a 32-byte secret drawn
 * from a cryptographic RNG.
 *
 * When a player calls {openPacks}, the contract:
 *   1. Pops the next commitment from the FIFO queue and binds it to the request.
 *   2. Records the request block number.
 *   3. Burns dMETH and emits {PackRequested}.
 *
 * After the anchor block has been mined, the operator calls
 * {fulfillPacks} with the matching pre-image. The contract verifies the
 * commitment, then derives the final randomness as:
 *
 *     randomNumber = keccak256(secret, blockhash(targetBlock), requestId)
 *
 * where `targetBlock = requestBlock + minRevealDelay` is fixed at request
 * time. Neither party can predict or bias the outcome:
 *   - The operator commits the secret before targetBlock is mined.
 *   - The player never learns the secret until the operator reveals.
 *   - Neither party can shop for a favorable block: the anchor is pinned
 *     to one specific block whose hash is determined the moment it is mined.
 *
 * The EVM blockhash horizon is 256 blocks, so reveals must happen within
 * ~51 minutes of `targetBlock` on mainnet. After that, the anchor becomes
 * inaccessible and the request must be refunded.
 *
 * GRIEFING & TIMEOUT
 * ------------------
 * If the operator for whatever reason does not reveal within 256 blocks of the anchor block,
 * `blockhash(targetBlock)` returns zero and the request is permanently
 * unfulfillable. The player can then call {refundExpiredRequest} to recover
 * the burned dMETH. The daily mint slot is NOT refunded (to keep accounting
 * simple); the worst-case wait is ~51 minutes on mainnet.
 *
 * OPERATOR INVARIANTS
 * -------------------
 *   * Secrets MUST be drawn from a CSPRNG and MUST NEVER be reused. Reusing a
 *     secret across two commitments lets anyone who sees the first reveal
 *     fulfill the second one.
 *   * Secrets MUST be kept secret until the reveal transaction is broadcast.
 *     Any leakage before reveal lets the player predict the outcome.
 *   * The operator should keep the commitment queue topped up; an exhausted
 *     queue causes {openPacks} to revert.
 */
contract Packs is Ownable, ReentrancyGuard {
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            STORAGE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    address public dmeth;
    address public minerNFT;
    address public miningSystem;

    /// @dev Off-chain service that commits secrets and broadcasts reveals.
    address public operator;

    /// @dev Blocks between request and the anchor block whose blockhash
    /// supplies the on-chain entropy. The anchor must be in the future at
    /// request time and in the past at reveal time. 2 covers shallow reorgs;
    /// raise for extra paranoia. Capped to leave room inside the 256-block
    /// blockhash window for the operator to actually broadcast the reveal.
    uint64 public minRevealDelay = 2;

    /// @dev EVM blockhash horizon. `blockhash(N)` returns zero once
    /// `block.number > N + 256`.
    uint256 public constant BLOCKHASH_WINDOW = 256;

    uint256 public packPrice = 125e18;
    uint256 public jackpotPortion = 25e18;
    uint256 public jackpotAccumulated;

    uint256 public dailyMintLimit = 3;
    uint64 public constant DAY = 1 days;

    mapping(address => uint64) public dailyWindowStart;
    mapping(address => uint256) public dailyMintCount;

    /// @dev FIFO queue of pre-committed hashes. `commitments[i]` is consumed
    /// when `nextCommitmentIndex == i`.
    bytes32[] public commitments;
    uint256 public nextCommitmentIndex;

    bool public mintLive = false;

    struct PackRequest {
        address player;
        uint8 packs;
        bool fulfilled;
        bool refunded;
        uint64 requestBlock;
        bytes32 commitment;
        uint256 cost; // dMETH burned, refundable on timeout
    }
    mapping(uint256 => PackRequest) public packRequests;

    /// @dev Monotonic request id counter.
    uint256 public nextRequestId;

    /// @dev Cumulative bounds on the 1,000,000 scale for miner indices 2..17.
    uint256[16] public dropBounds = [
        uint256(300000),  // 1: Nodester (idx 2)
        550000,           // 2: UnixDesktop (idx 3)
        720000,           // 3: GmForge (idx 4)
        840000,           // 4: EthStation (idx 5)
        905000,           // 5: BongHash (idx 6)
        940000,           // 6: NonceDaddy (idx 7)
        965000,           // 7: TheEqualizer (idx 8)
        980000,           // 8: Dual7800XT (idx 9)
        990000,           // 9: Triple3090TI (idx 10)
        995000,           // 10: HashIncubator (idx 11)
        997500,           // 11: Hyperion (idx 12)
        998700,           // 12: Resimulator (idx 13)
        999300,           // 13: Titanweaver (idx 14)
        999650,           // 14: Celesticore (idx 15)
        999850,           // 15: OmniNexus (idx 16)
        1000000           // 16: QuantumNode (idx 17)
    ];

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            EVENTS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    event CommitmentsAdded(uint256 fromIndex, uint256 count);
    event PackRequested(
        address indexed player,
        uint256 indexed requestId,
        uint8 packs,
        uint256 cost,
        bytes32 commitment,
        uint64 requestBlock
    );
    event PackFulfilled(uint256 indexed requestId, address indexed player, uint8 packs);
    event PackRefunded(uint256 indexed requestId, address indexed player, uint256 cost);
    event MinerDropped(
        uint256 indexed requestId,
        address indexed player,
        uint32 minerId,
        uint8 minerIndex,
        uint16 rarityMultiplierPct,
        uint32 finalHashrate,
        uint32 energy
    );

    event OperatorUpdated(address operator);
    event MintPacksToggled(bool mintLive);
    event RevealParamsUpdated(uint64 minRevealDelay);
    event PackPriceUpdated(uint256 packPrice, uint256 jackpotPortion);
    event DailyMintLimitUpdated(uint256 limit);
    event DropBoundUpdated(uint8 indexed slot, uint256 cumulativeBound);
    event ConfigUpdated(string indexed key, address value);

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            ERRORS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    error InvalidPackAmount();
    error DailyMintLimitReached();
    error RequestAlreadyFulfilled();
    error RequestAlreadyRefunded();
    error RequestNotFound();
    error NotConfigured();
    error ZeroAddress();
    error NoCommitmentsAvailable();
    error TooEarlyToReveal();
    error TooEarlyToRefund();
    error InvalidSecret();
    error NotOperator();
    error RevealWindowExpired();
    error MintNotLive();

    constructor() Ownable(msg.sender) {}

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //       OPERATOR FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Append a batch of pre-committed hashes to the FIFO queue.
    /// Each entry must be `keccak256(abi.encode(secret))` for a freshly
    /// generated 32-byte secret. The operator MUST keep the secrets stored
    /// securely off-chain until reveal time.
    function addCommitments(bytes32[] calldata hashes) external onlyOperator {
        uint256 start = commitments.length;
        for (uint256 i = 0; i < hashes.length; i++) {
            commitments.push(hashes[i]);
        }
        emit CommitmentsAdded(start, hashes.length);
    }

    /// @notice Reveal the secret for a pending request and mint the resulting
    /// Miner NFTs. Anyone may call this if they know the secret, but in
    /// practice only the operator does. The NFTs always go to the original
    /// requester regardless of caller.
    function fulfillPacks(uint256 requestId, bytes32 secret) external nonReentrant {
        PackRequest storage req = packRequests[requestId];
        if (req.player == address(0)) revert RequestNotFound();
        if (req.fulfilled) revert RequestAlreadyFulfilled();
        if (req.refunded) revert RequestAlreadyRefunded();

        uint256 targetBlock = uint256(req.requestBlock) + minRevealDelay;
        // Anchor block must already be in the past (blockhash(N) is zero when
        // N == block.number, so strict inequality).
        if (block.number <= targetBlock) revert TooEarlyToReveal();

        // Pin entropy to one specific past block. Once that block is mined,
        // its hash is fixed — the operator has no freedom to wait and shop
        // for a more favorable value.
        bytes32 anchor = blockhash(targetBlock);
        if (anchor == bytes32(0)) revert RevealWindowExpired();

        if (keccak256(abi.encode(secret)) != req.commitment) revert InvalidSecret();

        req.fulfilled = true;

        // Final randomness binds the operator-committed secret to the
        // pre-pinned anchor block hash. Neither party can predict it at
        // request time, and neither party has any choice over which block
        // contributes the entropy at reveal time.
        uint256 randomNumber = uint256(
            keccak256(abi.encode(secret, anchor, requestId))
        );

        address player = req.player;
        uint8 packs = req.packs;
        uint8 minerCount = IMiningSystemMint(miningSystem).uniqueMinerCount();

        for (uint256 i = 0; i < packs; i++) {
            uint256 r1 = uint256(keccak256(abi.encode(randomNumber, i, uint256(0))));
            uint256 r2 = uint256(keccak256(abi.encode(randomNumber, i, uint256(1))));

            uint8 minerIndex = _resolveMinerIndex(r1 % 1_000_000);
            // Defensive cap if mining system not fully seeded.
            if (minerIndex > minerCount) minerIndex = minerCount;

            uint16 mul = _resolveRarity(r2 % 10_000);

            (uint32 baseHash, uint32 energy, , ) = IMiningSystemMint(miningSystem).minerTemplates(minerIndex);
            uint32 finalHash = uint32((uint256(baseHash) * mul) / 100);

            uint32 minerId = IMiningSystemMint(miningSystem).reserveMinerId();
            IMinerNFTMint(minerNFT).mintMinerNFT(player, minerId, minerIndex, finalHash, energy);

            emit MinerDropped(requestId, player, minerId, minerIndex, mul, finalHash, energy);
        }

        emit PackFulfilled(requestId, player, packs);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         USER FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Open `packs` packs. `packs` must be 1, 5, or 10. The next
    /// commitment in the operator's queue is bound to this request.
    function openPacks(uint8 packs) external nonReentrant returns (uint256 requestId) {
        if (packs != 1 && packs != 5 && packs != 10) revert InvalidPackAmount();
        if (
            dmeth == address(0) || operator == address(0) ||
            minerNFT == address(0) || miningSystem == address(0)
        ) revert NotConfigured();
        if (!mintLive) revert MintNotLive();

        // Consume the next commitment. Reverts if the queue is empty —
        // the operator must keep it topped up.
        if (nextCommitmentIndex >= commitments.length) revert NoCommitmentsAvailable();
        bytes32 commitment = commitments[nextCommitmentIndex];
        unchecked { nextCommitmentIndex++; }

        _settleDailyWindow(msg.sender);
        if (dailyMintCount[msg.sender] + 1 > dailyMintLimit) revert DailyMintLimitReached();
        unchecked { dailyMintCount[msg.sender] += 1; }

        uint256 cost = packPrice * packs;
        if (packs == 5) cost -= jackpotPortion;
        if (packs == 10) cost -= jackpotPortion * 2;

        IDMeth(dmeth).burn(msg.sender, cost);
        jackpotAccumulated += jackpotPortion * packs;

        unchecked { requestId = ++nextRequestId; }
        packRequests[requestId] = PackRequest({
            player: msg.sender,
            packs: packs,
            fulfilled: false,
            refunded: false,
            requestBlock: uint64(block.number),
            commitment: commitment,
            cost: cost
        });

        emit PackRequested(msg.sender, requestId, packs, cost, commitment, uint64(block.number));
    }

    /// @notice Refund an unfulfilled request once the blockhash window has
    /// expired (~51 min after `targetBlock` on mainnet). Re-mints the burned
    /// dMETH to the original player and rolls back the jackpot accounting.
    /// Anyone may call (callable by keepers).
    ///
    /// Note: the daily mint slot is NOT refunded.

    function refundExpiredRequest(uint256 requestId) external nonReentrant {
        PackRequest storage req = packRequests[requestId];
        if (req.player == address(0)) revert RequestNotFound();
        if (req.fulfilled) revert RequestAlreadyFulfilled();
        if (req.refunded) revert RequestAlreadyRefunded();
        // Refund opens precisely when the anchor's blockhash is no longer
        // accessible on-chain — i.e., when the request is truly unfulfillable.
        uint256 deadline = uint256(req.requestBlock) + minRevealDelay + BLOCKHASH_WINDOW;
        if (block.number <= deadline) revert TooEarlyToRefund();

        req.refunded = true;

        uint256 jackpotShare = jackpotPortion * req.packs;
        if (jackpotAccumulated >= jackpotShare) {
            jackpotAccumulated -= jackpotShare;
        } else {
            jackpotAccumulated = 0;
        }

        IDMeth(dmeth).mint(req.player, req.cost);

        emit PackRefunded(requestId, req.player, req.cost);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        INTERNAL HELPERS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function _resolveMinerIndex(uint256 roll) internal view returns (uint8) {
        for (uint8 i = 0; i < 16; i++) {
            if (roll < dropBounds[i]) return i + 2;
        }
        return 17;
    }

    function _resolveRarity(uint256 roll) internal pure returns (uint16) {
        if (roll < 7600) return 100; // Common  76.00%
        if (roll < 9400) return 125; // Rare    18.00%
        if (roll < 9900) return 150; // Epic     5.00%
        return 200;                  // Mythic   1.00%
    }

    function _settleDailyWindow(address user) internal {
        uint64 ws = dailyWindowStart[user];
        if (ws == 0 || block.timestamp >= ws + DAY) {
            dailyWindowStart[user] = uint64(block.timestamp);
            dailyMintCount[user] = 0;
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         VIEW FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function remainingDailyMints(address user) external view returns (uint256) {
        uint64 ws = dailyWindowStart[user];
        if (ws == 0 || block.timestamp >= ws + DAY) return dailyMintLimit;
        uint256 used = dailyMintCount[user];
        return used >= dailyMintLimit ? 0 : dailyMintLimit - used;
    }

    function getDropBounds() external view returns (uint256[16] memory) {
        return dropBounds;
    }

    /// @notice Number of unused commitments remaining in the queue.
    function availableCommitments() external view returns (uint256) {
        return commitments.length - nextCommitmentIndex;
    }

    /// @notice True iff a request can be revealed now: target block has
    /// been mined and is still inside the blockhash window.
    function isRevealable(uint256 requestId) external view returns (bool) {
        PackRequest storage req = packRequests[requestId];
        if (req.player == address(0) || req.fulfilled || req.refunded) return false;
        uint256 targetBlock = uint256(req.requestBlock) + minRevealDelay;
        return block.number > targetBlock && block.number <= targetBlock + BLOCKHASH_WINDOW;
    }

    /// @notice True iff a request can be refunded now.
    function isRefundable(uint256 requestId) external view returns (bool) {
        PackRequest storage req = packRequests[requestId];
        if (req.player == address(0) || req.fulfilled || req.refunded) return false;
        return block.number > uint256(req.requestBlock) + minRevealDelay + BLOCKHASH_WINDOW;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        ADMIN FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    function toggleMintLive() external onlyOwner {
        mintLive = !mintLive;
        emit MintPacksToggled(mintLive);
    }

    function setRevealParams(uint64 _minRevealDelay) external onlyOwner {
        require(_minRevealDelay >= 1, "delay must be >= 1");
        // Cap to leave a wide window inside BLOCKHASH_WINDOW for the operator
        // to actually broadcast reveals. 64 blocks (~13 min) is a comfortable
        // upper bound; tune as needed.
        require(_minRevealDelay <= 64, "delay too large");
        minRevealDelay = _minRevealDelay;
        emit RevealParamsUpdated(_minRevealDelay);
    }

    function setPackPrice(uint256 _packPrice, uint256 _jackpotPortion) external onlyOwner {
        require(_jackpotPortion <= _packPrice, "jackpot > price");
        packPrice = _packPrice;
        jackpotPortion = _jackpotPortion;
        emit PackPriceUpdated(_packPrice, _jackpotPortion);
    }

    function setDailyMintLimit(uint256 _limit) external onlyOwner {
        dailyMintLimit = _limit;
        emit DailyMintLimitUpdated(_limit);
    }

    function setDropBound(uint8 slot, uint256 cumulativeBound) external onlyOwner {
        require(slot < 16, "slot");
        if (slot > 0) require(cumulativeBound > dropBounds[slot - 1], "non-increasing");
        if (slot < 15) require(cumulativeBound < dropBounds[slot + 1], "non-increasing");
        else require(cumulativeBound == 1_000_000, "last must be 1M");
        dropBounds[slot] = cumulativeBound;
        emit DropBoundUpdated(slot, cumulativeBound);
    }

    function setDMeth(address _dmeth) external onlyOwner {
        if (_dmeth == address(0)) revert ZeroAddress();
        dmeth = _dmeth;
        emit ConfigUpdated("dmeth", _dmeth);
    }

    function setMinerNFT(address _minerNFT) external onlyOwner {
        if (_minerNFT == address(0)) revert ZeroAddress();
        minerNFT = _minerNFT;
        emit ConfigUpdated("minerNFT", _minerNFT);
    }

    function setMiningSystem(address _miningSystem) external onlyOwner {
        if (_miningSystem == address(0)) revert ZeroAddress();
        miningSystem = _miningSystem;
        emit ConfigUpdated("miningSystem", _miningSystem);
    }
}
