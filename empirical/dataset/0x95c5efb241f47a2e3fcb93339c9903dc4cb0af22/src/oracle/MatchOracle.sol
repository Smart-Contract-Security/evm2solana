// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMatchOracle} from "./IMatchOracle.sol";
import {MatchTypes} from "./MatchTypes.sol";
import {IHatCard} from "../card/IHatCard.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {ProtocolPhase} from "../protocol/ProtocolPhase.sol";
import {Errors} from "../util/Errors.sol";

/// @title MatchOracle
/// @notice Canonical source of truth for per-player match statistics.
/// Whitepaper §05.
///
/// Lifecycle: SCHEDULED → LIVE → PROVISIONAL → SETTLED.
/// One-way per match; SETTLED stats are immutable.
///
/// Roles
/// -----
///   owner    — sets match metadata pre-match, can promote dispute → settle
///   reporter — single canonical address that posts stats
///   guardian — can flag a PROVISIONAL match into dispute; the reporter
///              reposts after correcting and the window restarts.
contract MatchOracle is Ownable, IMatchOracle {
    IProtocolRegistry public immutable registry;
    IHatCard          public immutable hatCard;

    address public reporter;
    address public guardian;
    uint64  public disputeWindowSecs;   // Δ_d from whitepaper §12

    struct MatchInfo {
        MatchTypes.Phase phase;
        uint64 kickoffAt;
        uint64 settleAt;          // when stats were posted (provisional)
        bool   disputed;
    }

    mapping(uint256 => MatchInfo) public matchInfo;
    mapping(uint256 => uint16[])  internal _playersInMatch;
    // matchId → playerId → stat → count
    mapping(uint256 => mapping(uint16 => mapping(uint8 => uint32))) internal _stats;

    event MatchScheduled(uint256 indexed matchId, uint64 kickoffAt);
    event MatchLive(uint256 indexed matchId);
    event MatchProvisional(uint256 indexed matchId, uint64 settleAt);
    event MatchDisputed(uint256 indexed matchId);
    event MatchSettled(uint256 indexed matchId);
    event StatsPosted(uint256 indexed matchId, uint16 indexed playerId);
    event ReporterSet(address reporter);
    event GuardianSet(address guardian);
    event DisputeWindowSet(uint64 secs);

    constructor(IProtocolRegistry _registry, IHatCard _hatCard, address _initialOwner)
        Ownable(_initialOwner)
    {
        registry          = _registry;
        hatCard           = _hatCard;
        disputeWindowSecs = 1 hours;       // sensible default; settable
    }

    // ─── admin ───────────────────────────────────────────────────────────

    function setReporter(address r) external onlyOwner {
        if (r == address(0)) revert Errors.ZeroAddress();
        reporter = r;
        emit ReporterSet(r);
    }

    function setGuardian(address g) external onlyOwner {
        if (g == address(0)) revert Errors.ZeroAddress();
        guardian = g;
        emit GuardianSet(g);
    }

    function setDisputeWindow(uint64 secs) external onlyOwner {
        disputeWindowSecs = secs;
        emit DisputeWindowSet(secs);
    }

    // ─── modifiers ───────────────────────────────────────────────────────

    modifier onlyReporter()  { if (msg.sender != reporter)  revert Errors.NotAuthorized(); _; }
    modifier onlyGuardian()  { if (msg.sender != guardian)  revert Errors.NotAuthorized(); _; }
    modifier onlyDuringLive() {
        ProtocolPhase.Phase p = registry.phase();
        if (uint8(p) < uint8(ProtocolPhase.Phase.LIVE) ||
            uint8(p) > uint8(ProtocolPhase.Phase.FULL_TIME)) revert Errors.WrongPhase();
        _;
    }

    // ─── lifecycle ───────────────────────────────────────────────────────

    /// @notice Owner schedules a match before it kicks off.
    function scheduleMatch(uint256 matchId, uint64 kickoffAt) external onlyOwner {
        MatchInfo storage m = matchInfo[matchId];
        if (m.phase != MatchTypes.Phase.SCHEDULED || m.kickoffAt != 0) revert Errors.AlreadyInitialised();
        m.kickoffAt = kickoffAt;
        emit MatchScheduled(matchId, kickoffAt);
    }

    /// @notice Reporter marks a match LIVE at kickoff. Reverts if called
    /// before the scheduled kickoff timestamp; a misbehaving reporter
    /// cannot mark a future match LIVE prematurely.
    function markLive(uint256 matchId) external onlyReporter onlyDuringLive {
        MatchInfo storage m = matchInfo[matchId];
        if (m.phase != MatchTypes.Phase.SCHEDULED) revert Errors.WrongPhase();
        if (m.kickoffAt != 0 && block.timestamp < m.kickoffAt) revert Errors.WrongPhase();
        m.phase = MatchTypes.Phase.LIVE;
        emit MatchLive(matchId);
    }

    /// @notice Reporter posts the per-player lines after full time. Moves
    /// the match into PROVISIONAL and opens the dispute window.
    function postStats(uint256 matchId, MatchTypes.PlayerLine[] calldata lines)
        external
        onlyReporter
        onlyDuringLive
    {
        MatchInfo storage m = matchInfo[matchId];
        // Allowed transitions: LIVE → PROVISIONAL (first post), or
        // PROVISIONAL (after a dispute) → PROVISIONAL (re-post with corrections).
        if (m.phase != MatchTypes.Phase.LIVE && m.phase != MatchTypes.Phase.PROVISIONAL) {
            revert Errors.WrongPhase();
        }
        // Clear previous player list (in case of dispute repost).
        delete _playersInMatch[matchId];

        for (uint256 i = 0; i < lines.length; ++i) {
            MatchTypes.PlayerLine calldata pl = lines[i];
            if (pl.playerId == 0) revert Errors.UnknownPlayer();
            _playersInMatch[matchId].push(pl.playerId);
            for (uint8 s = 0; s < 18; ++s) {
                _stats[matchId][pl.playerId][s] = pl.stats[s];
            }
            emit StatsPosted(matchId, pl.playerId);
        }

        m.phase    = MatchTypes.Phase.PROVISIONAL;
        m.settleAt = uint64(block.timestamp) + disputeWindowSecs;
        m.disputed = false;
        emit MatchProvisional(matchId, m.settleAt);
    }

    /// @notice Guardian flags a PROVISIONAL match. Blocks settlement until
    /// the reporter posts a corrected line.
    function flagDispute(uint256 matchId) external onlyGuardian {
        MatchInfo storage m = matchInfo[matchId];
        if (m.phase != MatchTypes.Phase.PROVISIONAL) revert Errors.WrongPhase();
        if (block.timestamp >= m.settleAt) revert Errors.WrongPhase();  // window closed
        m.disputed = true;
        // settleAt is left intact; the reporter will re-post and reset it.
        emit MatchDisputed(matchId);
    }

    /// @notice Permissionless: anyone may settle a match after the window
    /// elapses, provided no open dispute.
    function settle(uint256 matchId) external {
        MatchInfo storage m = matchInfo[matchId];
        if (m.phase != MatchTypes.Phase.PROVISIONAL) revert Errors.WrongPhase();
        if (block.timestamp < m.settleAt) revert Errors.WrongPhase();
        if (m.disputed) revert Errors.WrongPhase();
        m.phase = MatchTypes.Phase.SETTLED;
        emit MatchSettled(matchId);
    }

    // ─── read ────────────────────────────────────────────────────────────

    function phaseOf(uint256 matchId) external view override returns (MatchTypes.Phase) {
        return matchInfo[matchId].phase;
    }

    function statOf(uint256 matchId, uint16 playerId, MatchTypes.Stat stat)
        external
        view
        override
        returns (uint32)
    {
        return _stats[matchId][playerId][uint8(stat)];
    }

    function playersInMatch(uint256 matchId) external view override returns (uint16[] memory) {
        return _playersInMatch[matchId];
    }

    function disputeDeadline(uint256 matchId) external view override returns (uint64) {
        return matchInfo[matchId].settleAt;
    }
}
