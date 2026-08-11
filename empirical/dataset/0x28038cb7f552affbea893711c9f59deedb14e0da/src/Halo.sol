// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ============================================================================
//   Halo — on-chain ETH lottery for Telegram Mini Apps
//
//   Official socials (anything else is a scam — DO NOT trust links from DMs):
//     Telegram : https://t.me/HaloEthereum
//     X        : https://x.com/HaloEthereum
// ============================================================================

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Halo — Telegram Mini App lottery
/// @notice Fixed-duration ETH rounds settled by Chainlink VRF v2.5.
/// @custom:telegram https://t.me/HaloEthereum
/// @custom:twitter https://x.com/HaloEthereum
contract Halo is VRFConsumerBaseV2Plus, Pausable, ReentrancyGuard {
    // -------- Errors --------
    error WrongEntryFee(uint256 sent, uint256 expected);
    error RoundNotOpen(uint256 roundId);
    error RoundNotEnded(uint64 endTime, uint64 nowTs);
    error RoundAlreadyEnded(uint256 roundId);
    error RoundNotPendingVrf(uint256 roundId);
    error RoundNotCompleted(uint256 roundId);
    error RoundNotRefunded(uint256 roundId);
    error NotWinner(address caller, address winner);
    error AlreadyClaimed(uint256 roundId);
    error NothingToRefund(uint256 roundId, address player);
    error InvalidConfig();
    error TransferFailed();
    error UnknownVrfRequest(uint256 requestId);
    error MaxPlayersReached(uint256 roundId, uint32 max);
    error VrfNotStuckYet(uint64 unlockAt, uint64 nowTs);

    // -------- Types --------
    enum Status {
        OPEN,
        PENDING_VRF,
        COMPLETED,
        REFUNDED
    }

    struct Round {
        uint256 id;
        uint64 startTime;
        uint64 endTime;
        uint128 pot;
        uint128 prizeAmount; // snapshot at fulfillment
        // Entry fee snapshot at the moment the round started. Decouples
        // refund/validation from `entryFee` storage so mid-round fee changes
        // don't break already-paid entries.
        uint256 entryFee;
        address winner;
        address trigger; // who called requestRoundEnd
        uint256 vrfRequestId;
        Status status;
        bool claimed;
        uint32 uniquePlayers;
        address[] players;
    }

    // -------- Constants --------
    uint16 public constant MAX_HOUSE_FEE_BPS = 1000; // 10%
    uint16 public constant MAX_CALLER_INCENTIVE_BPS = 200; // 2%
    uint16 public constant BPS_DENOM = 10_000;
    /// @notice Owner can force-refund a PENDING_VRF round after this much time
    /// has elapsed past its endTime — the escape hatch for cases where the VRF
    /// coordinator never fulfils (sub out of LINK, outage, etc.).
    uint256 public constant VRF_STUCK_TIMEOUT = 1 days;
    /// @notice After this longer window, anyone (not just owner) can rescue a
    /// stuck PENDING_VRF round. Protects players if the owner key is lost or
    /// compromised — funds can never be permanently frozen.
    uint256 public constant VRF_STUCK_TIMEOUT_PERMISSIONLESS = 7 days;
    /// @notice Hard upper bound on `maxPlayersPerRound` to keep the VRF
    /// callback's gas usage bounded even if admin sets a silly value.
    uint32 public constant ABSOLUTE_MAX_PLAYERS = 10_000;

    // -------- Config --------
    uint256 public entryFee;
    uint16 public houseFeeBps;
    uint16 public callerIncentiveBps;
    uint32 public roundDuration;
    uint8 public minPlayers;
    address public treasury;
    /// @notice Hard cap on entries per round. Protects the VRF callback from
    /// running out of gas on a giant `players` array. Capped at
    /// `ABSOLUTE_MAX_PLAYERS` by setters.
    uint32 public maxPlayersPerRound;

    // VRF
    uint256 public vrfSubscriptionId;
    bytes32 public vrfKeyHash;
    uint32 public vrfCallbackGasLimit;
    uint16 public vrfRequestConfirmations;

    // -------- State --------
    uint256 public currentRoundId;
    mapping(uint256 => Round) private _rounds;
    mapping(uint256 => uint256) public vrfRequestToRound; // requestId => roundId
    /// @notice Whether a given VRF requestId was issued by this contract.
    /// Decoupled from `vrfRequestToRound` so the "unknown request" check no
    /// longer collides with `roundId == 0`.
    mapping(uint256 => bool) public vrfRequestKnown;
    mapping(uint256 => mapping(address => uint256)) public entries; // round => player => count
    uint256 public accruedTreasury;

    // -------- Events --------
    event RoundStarted(uint256 indexed roundId, uint64 startTime, uint64 endTime);
    event PlayerJoined(uint256 indexed roundId, address indexed player, uint32 position, uint128 newPot);
    event RoundEndRequested(uint256 indexed roundId, uint256 indexed vrfRequestId, address indexed trigger);
    event WinnerPicked(uint256 indexed roundId, address indexed winner, uint256 prizeAmount, uint256 houseFee);
    event RoundRefunded(uint256 indexed roundId, string reason);
    event Claimed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event Refunded(uint256 indexed roundId, address indexed player, uint256 amount);
    event CallerIncentivePaid(uint256 indexed roundId, address indexed caller, uint256 amount);
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event ConfigUpdated(string indexed key);

    // -------- Constructor --------
    struct InitConfig {
        uint256 entryFee;
        uint16 houseFeeBps;
        uint16 callerIncentiveBps;
        uint32 roundDuration;
        uint8 minPlayers;
        uint32 maxPlayersPerRound;
        address treasury;
        address vrfCoordinator;
        uint256 vrfSubscriptionId;
        bytes32 vrfKeyHash;
        uint32 vrfCallbackGasLimit;
        uint16 vrfRequestConfirmations;
    }

    constructor(InitConfig memory cfg) VRFConsumerBaseV2Plus(cfg.vrfCoordinator) {
        if (
            cfg.entryFee == 0 || cfg.houseFeeBps > MAX_HOUSE_FEE_BPS
                || cfg.callerIncentiveBps > MAX_CALLER_INCENTIVE_BPS || cfg.roundDuration < 60 || cfg.minPlayers < 2
                || cfg.maxPlayersPerRound < cfg.minPlayers || cfg.maxPlayersPerRound > ABSOLUTE_MAX_PLAYERS
                || cfg.treasury == address(0)
        ) revert InvalidConfig();

        entryFee = cfg.entryFee;
        houseFeeBps = cfg.houseFeeBps;
        callerIncentiveBps = cfg.callerIncentiveBps;
        roundDuration = cfg.roundDuration;
        minPlayers = cfg.minPlayers;
        maxPlayersPerRound = cfg.maxPlayersPerRound;
        treasury = cfg.treasury;

        vrfSubscriptionId = cfg.vrfSubscriptionId;
        vrfKeyHash = cfg.vrfKeyHash;
        vrfCallbackGasLimit = cfg.vrfCallbackGasLimit;
        vrfRequestConfirmations = cfg.vrfRequestConfirmations;

        _startNewRound();
    }

    // -------- Player actions --------

    function joinRound() external payable whenNotPaused {
        _join(msg.sender);
    }

    /// @notice Join on behalf of another address. Callable by anyone — useful
    /// for a relayer that watches a deposit address and forwards entries to
    /// players who can't sign transactions (e.g. Telegram Mini App users on
    /// mobile). The recorded `player` is the one credited with the entry and
    /// later able to call `claim()` if they win.
    function joinRoundFor(address player) external payable whenNotPaused {
        if (player == address(0)) revert InvalidConfig();
        _join(player);
    }

    function _join(address player) internal {
        uint256 roundId = currentRoundId;
        Round storage r = _rounds[roundId];
        // Validate against the round's snapshot fee, not the live `entryFee`
        // (which an admin may have changed mid-round).
        if (msg.value != r.entryFee) revert WrongEntryFee(msg.value, r.entryFee);
        if (r.status != Status.OPEN) revert RoundNotOpen(roundId);
        if (block.timestamp >= r.endTime) revert RoundAlreadyEnded(roundId);
        uint32 cap = maxPlayersPerRound;
        if (r.players.length >= cap) revert MaxPlayersReached(roundId, cap);

        uint32 position = uint32(r.players.length);
        r.players.push(player);
        r.pot += uint128(msg.value);
        uint256 prevEntries = entries[roundId][player];
        if (prevEntries == 0) {
            unchecked {
                r.uniquePlayers += 1;
            }
        }
        unchecked {
            entries[roundId][player] = prevEntries + 1;
        }

        emit PlayerJoined(roundId, player, position, r.pot);
    }

    function requestRoundEnd(uint256 roundId) external {
        Round storage r = _rounds[roundId];
        if (r.status != Status.OPEN) revert RoundNotOpen(roundId);
        if (block.timestamp < r.endTime) revert RoundNotEnded(r.endTime, uint64(block.timestamp));

        if (r.uniquePlayers < minPlayers) {
            r.status = Status.REFUNDED;
            emit RoundRefunded(roundId, "insufficient_players");
            _startNewRound();
            return;
        }

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        r.vrfRequestId = requestId;
        r.status = Status.PENDING_VRF;
        r.trigger = msg.sender;
        vrfRequestToRound[requestId] = roundId;
        vrfRequestKnown[requestId] = true;

        emit RoundEndRequested(roundId, requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (!vrfRequestKnown[requestId]) revert UnknownVrfRequest(requestId);
        uint256 roundId = vrfRequestToRound[requestId];
        Round storage r = _rounds[roundId];
        if (r.status != Status.PENDING_VRF) revert RoundNotPendingVrf(roundId);

        address winner = r.players[randomWords[0] % r.players.length];
        r.winner = winner;
        r.status = Status.COMPLETED;

        uint256 pot = r.pot;
        uint256 houseFee = (pot * houseFeeBps) / BPS_DENOM;
        uint256 callerFee = (pot * callerIncentiveBps) / BPS_DENOM;
        uint256 prize = pot - houseFee - callerFee;
        r.prizeAmount = uint128(prize);

        accruedTreasury += houseFee;

        address triggerCaller = r.trigger;
        if (callerFee > 0) {
            if (triggerCaller == address(0)) {
                accruedTreasury += callerFee;
            } else {
                (bool ok,) = triggerCaller.call{value: callerFee, gas: 30_000}("");
                if (!ok) {
                    accruedTreasury += callerFee;
                } else {
                    emit CallerIncentivePaid(roundId, triggerCaller, callerFee);
                }
            }
        }

        emit WinnerPicked(roundId, winner, prize, houseFee);

        // Auto-push prize to the winner. EOAs (mobile MetaMask, etc.) accept ETH
        // with no code execution; smart contracts may need more gas than the
        // 30k cap and will fall back to the pull `claim()` flow. Gas is capped
        // so a malicious recipient can't DoS the VRF callback.
        (bool pushed,) = winner.call{value: prize, gas: 30_000}("");
        if (pushed) {
            r.claimed = true;
            emit Claimed(roundId, winner, prize);
        }

        _startNewRound();
    }

    function claim(uint256 roundId) external nonReentrant {
        Round storage r = _rounds[roundId];
        if (r.status != Status.COMPLETED) revert RoundNotCompleted(roundId);
        if (r.claimed) revert AlreadyClaimed(roundId);
        if (msg.sender != r.winner) revert NotWinner(msg.sender, r.winner);

        r.claimed = true;
        uint256 prize = r.prizeAmount;

        (bool ok,) = msg.sender.call{value: prize}("");
        if (!ok) revert TransferFailed();

        emit Claimed(roundId, msg.sender, prize);
    }

    function refund(uint256 roundId) external nonReentrant {
        Round storage r = _rounds[roundId];
        if (r.status != Status.REFUNDED) revert RoundNotRefunded(roundId);

        uint256 count = entries[roundId][msg.sender];
        if (count == 0) revert NothingToRefund(roundId, msg.sender);
        entries[roundId][msg.sender] = 0;

        // Use the round's snapshot fee so refunds always match what was paid,
        // regardless of any admin `setEntryFee` since.
        uint256 amount = count * r.entryFee;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Refunded(roundId, msg.sender, amount);
    }

    // -------- Views --------

    /// @notice Clean struct view over a round. Preferred over the legacy
    /// 12-field tuple `getRound` for indexers/clients — same data, much easier
    /// ABI to consume.
    struct RoundView {
        uint256 id;
        uint64 startTime;
        uint64 endTime;
        uint128 pot;
        uint128 prizeAmount;
        uint256 entryFee;
        address winner;
        address trigger;
        uint256 vrfRequestId;
        Status status;
        bool claimed;
        uint32 playerCount;
        uint32 uniquePlayers;
    }

    function getRoundInfo(uint256 roundId) external view returns (RoundView memory) {
        Round storage r = _rounds[roundId];
        return RoundView({
            id: r.id,
            startTime: r.startTime,
            endTime: r.endTime,
            pot: r.pot,
            prizeAmount: r.prizeAmount,
            entryFee: r.entryFee,
            winner: r.winner,
            trigger: r.trigger,
            vrfRequestId: r.vrfRequestId,
            status: r.status,
            claimed: r.claimed,
            playerCount: uint32(r.players.length),
            uniquePlayers: r.uniquePlayers
        });
    }

    function getRound(uint256 roundId)
        external
        view
        returns (
            uint256 id,
            uint64 startTime,
            uint64 endTime,
            uint128 pot,
            uint128 prizeAmount,
            address winner,
            address trigger,
            uint256 vrfRequestId,
            Status status,
            bool claimed,
            uint32 playerCount,
            uint32 uniquePlayers
        )
    {
        Round storage r = _rounds[roundId];
        return (
            r.id,
            r.startTime,
            r.endTime,
            r.pot,
            r.prizeAmount,
            r.winner,
            r.trigger,
            r.vrfRequestId,
            r.status,
            r.claimed,
            uint32(r.players.length),
            r.uniquePlayers
        );
    }

    /// @notice Entry fee snapshot for a round — useful for clients who need to
    /// reconstruct what players paid, regardless of any admin `setEntryFee` since.
    function getRoundEntryFee(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].entryFee;
    }

    function getPlayers(uint256 roundId) external view returns (address[] memory) {
        return _rounds[roundId].players;
    }

    function getPlayerAt(uint256 roundId, uint256 index) external view returns (address) {
        return _rounds[roundId].players[index];
    }

    /// @notice Paginated view over the players list. Use this for rounds with
    /// thousands of entries — the full `getPlayers()` call can exceed an
    /// eth_call gas limit on big rounds.
    function getPlayersRange(uint256 roundId, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory slice)
    {
        address[] storage all = _rounds[roundId].players;
        uint256 total = all.length;
        if (offset >= total) return new address[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 n = end - offset;
        slice = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            slice[i] = all[offset + i];
        }
    }

    // -------- Admin --------

    function setEntryFee(uint256 newFee) external onlyOwner {
        if (newFee == 0) revert InvalidConfig();
        entryFee = newFee;
        emit ConfigUpdated("entryFee");
    }

    function setHouseFeeBps(uint16 newBps) external onlyOwner {
        if (newBps > MAX_HOUSE_FEE_BPS) revert InvalidConfig();
        houseFeeBps = newBps;
        emit ConfigUpdated("houseFeeBps");
    }

    function setCallerIncentiveBps(uint16 newBps) external onlyOwner {
        if (newBps > MAX_CALLER_INCENTIVE_BPS) revert InvalidConfig();
        callerIncentiveBps = newBps;
        emit ConfigUpdated("callerIncentiveBps");
    }

    function setMinPlayers(uint8 newMin) external onlyOwner {
        if (newMin < 2 || newMin > maxPlayersPerRound) revert InvalidConfig();
        minPlayers = newMin;
        emit ConfigUpdated("minPlayers");
    }

    function setMaxPlayersPerRound(uint32 newMax) external onlyOwner {
        if (newMax < minPlayers || newMax > ABSOLUTE_MAX_PLAYERS) revert InvalidConfig();
        maxPlayersPerRound = newMax;
        emit ConfigUpdated("maxPlayersPerRound");
    }

    function setRoundDuration(uint32 newDuration) external onlyOwner {
        if (newDuration < 60) revert InvalidConfig();
        roundDuration = newDuration;
        emit ConfigUpdated("roundDuration");
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidConfig();
        treasury = newTreasury;
        emit ConfigUpdated("treasury");
    }

    function updateVrfConfig(
        uint256 newSubId,
        bytes32 newKeyHash,
        uint32 newCallbackGasLimit,
        uint16 newRequestConfirmations
    ) external onlyOwner {
        vrfSubscriptionId = newSubId;
        vrfKeyHash = newKeyHash;
        vrfCallbackGasLimit = newCallbackGasLimit;
        vrfRequestConfirmations = newRequestConfirmations;
        emit ConfigUpdated("vrf");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Escape hatch: force a stuck PENDING_VRF round into REFUNDED so
    /// players can pull their entries back. Callable by owner only, and only
    /// after VRF_STUCK_TIMEOUT has elapsed past the round's endTime. Starts a
    /// new round so the lottery resumes immediately. Idempotent against a late
    /// VRF callback — that callback will simply revert (status != PENDING_VRF).
    function forceRefundStuckRound(uint256 roundId) external onlyOwner {
        _forceRefund(roundId, VRF_STUCK_TIMEOUT, "vrf_timeout");
    }

    /// @notice Permissionless escape hatch — anyone can rescue a stuck round
    /// after `VRF_STUCK_TIMEOUT_PERMISSIONLESS` (7 days) has elapsed past
    /// `endTime`. Protects players if the owner key is lost or compromised:
    /// funds can never be permanently frozen because of admin inaction.
    function forceRefundStuckRoundPermissionless(uint256 roundId) external {
        _forceRefund(roundId, VRF_STUCK_TIMEOUT_PERMISSIONLESS, "vrf_timeout_permissionless");
    }

    function _forceRefund(uint256 roundId, uint256 timeout, string memory reason) internal {
        Round storage r = _rounds[roundId];
        if (r.status != Status.PENDING_VRF) revert RoundNotPendingVrf(roundId);
        uint64 unlock = r.endTime + uint64(timeout);
        if (block.timestamp < unlock) revert VrfNotStuckYet(unlock, uint64(block.timestamp));
        r.status = Status.REFUNDED;
        emit RoundRefunded(roundId, reason);
        _startNewRound();
    }

    function withdrawTreasury() external nonReentrant {
        uint256 amount = accruedTreasury;
        if (amount == 0) return;
        accruedTreasury = 0;
        (bool ok,) = treasury.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit TreasuryWithdrawn(treasury, amount);
    }

    // -------- Internal --------

    function _startNewRound() internal {
        uint256 newId;
        unchecked {
            newId = currentRoundId + 1;
        }
        currentRoundId = newId;

        Round storage r = _rounds[newId];
        r.id = newId;
        r.startTime = uint64(block.timestamp);
        r.endTime = uint64(block.timestamp + roundDuration);
        r.entryFee = entryFee; // snapshot — protects players from mid-round fee changes
        r.status = Status.OPEN;

        emit RoundStarted(newId, r.startTime, r.endTime);
    }

    receive() external payable {
        revert();
    }
}
