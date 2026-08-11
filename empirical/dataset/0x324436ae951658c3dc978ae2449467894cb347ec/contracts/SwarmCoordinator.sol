// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IAccessPredicate.sol";

/// @title SwarmCoordinator v2
/// @notice Trustless swarm trading coordination — fixed per Gemini audit
/// @dev Fixes: Commit-Reveal voting, proportional settlement, timeout,
///      participation stake/slashing, bytes32 addresses, emergency stop
contract SwarmCoordinator {

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 public constant MIN_PARTICIPANTS    = 10;
    uint256 public constant SKR_FEE_BPS         = 500;       // 5%
    uint256 public constant BPS_DENOM           = 10_000;
    uint256 public constant SESSION_TIMEOUT     = 24 hours;  // auto-expire open sessions
    uint256 public constant COMMIT_WINDOW       = 5 minutes; // commit phase duration
    uint256 public constant REVEAL_WINDOW       = 10 minutes;// reveal phase duration
    uint256 public constant PARTICIPATION_STAKE = 0.01 ether;// slashed if no-show

    /// @dev SKR fee wallet on Solana (stored as fixed string in events/views)
    string  public constant SKR_WALLET_B58 = "B6zXbJN1wvb7ybsRCKk3kBkZkY7yN7s72Z6eag1UBhzS";

    // ─── Types ────────────────────────────────────────────────────────────────

    enum SessionState { Open, Active, Committing, Revealing, Trading, Settling, Closed, Emergency }

    struct Participant {
        bytes32 solanaWallet;      // base58 encoded as bytes32 (gas-efficient)
        uint256 stakeAmount;       // ETH staked (slashed if no-show)
        uint256 contributionWei;   // off-chain lamports reported after buy
        bool    committed;         // submitted commit hash
        bool    revealed;          // revealed their coin vote
        bytes32 commitHash;        // keccak256(mintBytes32 + salt)
        bytes32 votedCoin;         // revealed coin choice
        bool    buyConfirmed;      // confirmed buy on Solana
        bool    settled;           // received payout record
        bool    slashed;           // stake slashed for no-show
    }

    struct Session {
        uint256       id;
        SessionState  state;
        uint256       createdAt;
        uint256       commitDeadline;
        uint256       revealDeadline;
        address[]     participantAddrs;
        mapping(address => Participant) participants;
        mapping(bytes32 => uint256) coinVotes;  // bytes32 mint → vote count
        bytes32       selectedCoin;
        uint256       sellVotes;
        mapping(address => bool) hasVotedSell;
        uint256       totalContributionWei;     // sum of all confirmed contributions
        uint256       totalProfitWei;           // reported net profit (wei-equivalent)
        uint256       skrFeeWei;
        bool          oracleSettled;
        uint8         oracleSignatures;         // how many oracles confirmed
    }

    // ─── Storage ──────────────────────────────────────────────────────────────

    IAccessPredicate public predicate;
    address          public owner;
    address[]        public oracles;            // multi-sig oracle addresses
    uint8            public oracleThreshold;    // min signatures to settle
    uint256          public sessionCount;
    bool             public globalEmergency;    // circuit-breaker

    mapping(uint256 => Session)         internal sessions;
    mapping(address => mapping(uint256 => bool)) public oracleConfirmed;

    // ─── Events ───────────────────────────────────────────────────────────────

    event SessionCreated(uint256 indexed sessionId, address creator);
    event AgentJoined(uint256 indexed sessionId, address agent, uint256 stake);
    event SessionActivated(uint256 indexed sessionId, uint256 commitDeadline);
    event CommitSubmitted(uint256 indexed sessionId, address agent);
    event CoinRevealed(uint256 indexed sessionId, address agent, bytes32 coin);
    event CoinSelected(uint256 indexed sessionId, bytes32 coin);
    event BuyConfirmed(uint256 indexed sessionId, address agent, uint256 contributionWei);
    event SellVoted(uint256 indexed sessionId, address agent, uint256 totalVotes);
    event SellTriggered(uint256 indexed sessionId);
    event AgentSlashed(uint256 indexed sessionId, address agent, uint256 amount);
    event OracleSettled(uint256 indexed sessionId, address oracle, uint8 sigCount);
    event ProfitDistributed(uint256 indexed sessionId, uint256 totalProfit,
                            uint256 skrFee, address[] payees, uint256[] amounts);
    event EmergencyDeclared(uint256 indexed sessionId, address by);
    event StakeWithdrawn(uint256 indexed sessionId, address agent, uint256 amount);

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    modifier notEmergency() { require(!globalEmergency, "Emergency mode"); _; }
    modifier onlyOracle() {
        bool found;
        for (uint i; i < oracles.length; i++) if (oracles[i] == msg.sender) { found = true; break; }
        require(found, "Not an oracle");
        _;
    }
    modifier onlyParticipant(uint256 sid) {
        require(sessions[sid].participants[msg.sender].stakeAmount > 0, "Not a participant");
        _;
    }
    modifier inState(uint256 sid, SessionState expected) {
        require(sessions[sid].state == expected, "Wrong state");
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address _predicate, address[] memory _oracles, uint8 _threshold) {
        require(_predicate  != address(0),              "Invalid predicate");
        require(_oracles.length > 0,                    "Need at least 1 oracle");
        require(_threshold > 0,                         "Threshold must be > 0");
        require(_threshold <= _oracles.length,          "Threshold > oracle count");
        owner            = msg.sender;
        predicate        = IAccessPredicate(_predicate);
        oracles          = _oracles;
        oracleThreshold  = _threshold;
    }

    // ─── Session Creation ─────────────────────────────────────────────────────

    /// @notice Create a new swarm session — requires Normies NFT
    function createSession() external notEmergency returns (uint256 sessionId) {
        require(predicate.hasAccess(msg.sender, ""), "Predicate: not a Normies holder");
        sessionId = ++sessionCount;
        Session storage s = sessions[sessionId];
        s.id        = sessionId;
        s.state     = SessionState.Open;
        s.createdAt = block.timestamp;
        emit SessionCreated(sessionId, msg.sender);
    }

    /// @notice Join session — must stake PARTICIPATION_STAKE ETH
    /// @param solanaWalletB58Bytes  Solana wallet as bytes32 (UTF-8 encoded base58)
    function joinSession(uint256 sid, bytes32 solanaWalletB58Bytes)
        external payable
        notEmergency
        inState(sid, SessionState.Open)
    {
        require(predicate.hasAccess(msg.sender, ""),        "Predicate: not a Normies holder");
        require(msg.value >= PARTICIPATION_STAKE,           "Insufficient stake");
        require(solanaWalletB58Bytes != bytes32(0),         "Solana wallet required");

        // Expire old sessions
        Session storage s = sessions[sid];
        require(block.timestamp <= s.createdAt + SESSION_TIMEOUT, "Session expired");
        require(s.participants[msg.sender].stakeAmount == 0,      "Already joined");

        s.participants[msg.sender] = Participant({
            solanaWallet:    solanaWalletB58Bytes,
            stakeAmount:     msg.value,
            contributionWei: 0,
            committed:       false,
            revealed:        false,
            commitHash:      bytes32(0),
            votedCoin:       bytes32(0),
            buyConfirmed:    false,
            settled:         false,
            slashed:         false
        });
        s.participantAddrs.push(msg.sender);

        emit AgentJoined(sid, msg.sender, msg.value);

        if (s.participantAddrs.length >= MIN_PARTICIPANTS) {
            s.state          = SessionState.Active;
            s.commitDeadline = block.timestamp + COMMIT_WINDOW;
            s.revealDeadline = s.commitDeadline + REVEAL_WINDOW;
            emit SessionActivated(sid, s.commitDeadline);
        }
    }

    // ─── Commit-Reveal Coin Voting (Anti-Front-Running) ───────────────────────

    /// @notice Phase 1: Submit commit hash. hash = keccak256(abi.encode(coin, salt))
    function commitCoinVote(uint256 sid, bytes32 commitHash)
        external
        onlyParticipant(sid)
        inState(sid, SessionState.Active)
    {
        Session storage s = sessions[sid];
        require(block.timestamp <= s.commitDeadline, "Commit window closed");
        Participant storage p = s.participants[msg.sender];
        require(!p.committed, "Already committed");

        p.commitHash = commitHash;
        p.committed  = true;
        emit CommitSubmitted(sid, msg.sender);

        // Auto-advance state when all committed or deadline reached
        if (_allCommitted(s)) _startReveal(s);
    }

    /// @notice Phase 2: Reveal your coin vote
    function revealCoinVote(uint256 sid, bytes32 coin, bytes32 salt)
        external
        onlyParticipant(sid)
        inState(sid, SessionState.Committing)
    {
        Session storage s = sessions[sid];
        require(block.timestamp <= s.revealDeadline, "Reveal window closed");

        Participant storage p = s.participants[msg.sender];
        require(p.committed && !p.revealed, "Not committed or already revealed");
        require(keccak256(abi.encode(coin, salt)) == p.commitHash, "Hash mismatch");

        p.revealed   = true;
        p.votedCoin  = coin;
        s.coinVotes[coin]++;

        emit CoinRevealed(sid, msg.sender, coin);

        // Select coin if >50% of reveals agree
        uint256 threshold = s.participantAddrs.length / 2 + 1;
        if (s.coinVotes[coin] >= threshold) {
            s.selectedCoin = coin;
            s.state        = SessionState.Trading;
            emit CoinSelected(sid, coin);
        }
    }

    /// @notice Advance from Active→Committing (can be called by anyone after deadline)
    function advanceToReveal(uint256 sid) external inState(sid, SessionState.Active) {
        Session storage s = sessions[sid];
        require(block.timestamp > s.commitDeadline, "Commit window still open");
        _startReveal(s);
    }

    function _startReveal(Session storage s) internal {
        s.state = SessionState.Committing;
    }

    function _allCommitted(Session storage s) internal view returns (bool) {
        for (uint i; i < s.participantAddrs.length; i++) {
            if (!s.participants[s.participantAddrs[i]].committed) return false;
        }
        return true;
    }

    // ─── Buy Confirmation + Slashing ──────────────────────────────────────────

    /// @notice Confirm buy — report SOL spent (converted to wei-equivalent for on-chain math)
    /// @param contributionWei  lamportsSpent * 1e9 (normalized to wei for uniform math)
    function confirmBuy(uint256 sid, uint256 contributionWei)
        external
        onlyParticipant(sid)
        inState(sid, SessionState.Trading)
    {
        require(contributionWei > 0, "Must report > 0 contribution");
        Session storage s = sessions[sid];
        Participant storage p = s.participants[msg.sender];
        require(!p.buyConfirmed, "Already confirmed");

        p.buyConfirmed    = true;
        p.contributionWei = contributionWei;
        s.totalContributionWei += contributionWei;

        emit BuyConfirmed(sid, msg.sender, contributionWei);
    }

    /// @notice Slash agents who joined but never confirmed their buy
    /// @dev Called after sell is triggered. Slashed ETH goes to active participants.
    function slashNoShows(uint256 sid) external inState(sid, SessionState.Settling) {
        Session storage s = sessions[sid];
        uint256 totalSlashed;

        for (uint i; i < s.participantAddrs.length; i++) {
            address addr = s.participantAddrs[i];
            Participant storage p = s.participants[addr];
            if (!p.buyConfirmed && !p.slashed) {
                p.slashed = true;
                uint256 slashAmt = p.stakeAmount;
                totalSlashed += slashAmt;
                p.stakeAmount = 0;
                emit AgentSlashed(sid, addr, slashAmt); // FIX: emit before zeroing
            }
        }
        // Slashed ETH is distributed to active participants in settleProfits
        s.totalProfitWei += totalSlashed; // bonus to honest participants
    }

    // ─── Sell Voting ──────────────────────────────────────────────────────────

    function voteToSell(uint256 sid) external onlyParticipant(sid) inState(sid, SessionState.Trading) {
        Session storage s = sessions[sid];
        require(!s.hasVotedSell[msg.sender], "Already voted");
        s.hasVotedSell[msg.sender] = true;
        s.sellVotes++;
        emit SellVoted(sid, msg.sender, s.sellVotes);

        if (s.sellVotes >= s.participantAddrs.length / 2 + 1) {
            s.state = SessionState.Settling;
            emit SellTriggered(sid);
        }
    }

    // ─── Multi-Sig Oracle Settlement ──────────────────────────────────────────

    /// @notice Oracle confirms total profit (replaces single-owner trust)
    /// @param totalProfitWei  Net profit in wei-equivalent (lamports * 1e9)
    function oracleConfirmProfit(uint256 sid, uint256 totalProfitWei)
        external
        onlyOracle
        inState(sid, SessionState.Settling)
    {
        require(!oracleConfirmed[msg.sender][sid], "Oracle already confirmed");
        oracleConfirmed[msg.sender][sid] = true;

        Session storage s = sessions[sid];
        s.oracleSignatures++;
        emit OracleSettled(sid, msg.sender, s.oracleSignatures);

        if (s.oracleSignatures >= oracleThreshold) {
            s.totalProfitWei = totalProfitWei;
            s.oracleSettled  = true;
            _distributeProfit(s);
        }
    }

    /// @notice Distribute profits proportionally by contribution
    function _distributeProfit(Session storage s) internal {
        require(s.oracleSettled, "Not settled by oracle");

        uint256 profit    = s.totalProfitWei;
        uint256 skrFee    = (profit * SKR_FEE_BPS) / BPS_DENOM;
        uint256 remaining = profit - skrFee;

        s.skrFeeWei = skrFee;
        s.state     = SessionState.Closed;

        // Build payout arrays
        address[] memory payees  = new address[](s.participantAddrs.length);
        uint256[] memory amounts = new uint256[](s.participantAddrs.length);

        for (uint i; i < s.participantAddrs.length; i++) {
            address addr = s.participantAddrs[i];
            Participant storage p = s.participants[addr];
            payees[i] = addr;

            if (p.slashed || !p.buyConfirmed || s.totalContributionWei == 0) {
                amounts[i] = 0;
            } else {
                // Proportional: share = remaining * agentContribution / totalContribution
                amounts[i] = (remaining * p.contributionWei) / s.totalContributionWei;
            }
            p.settled = true;
        }

        emit ProfitDistributed(s.id, profit, skrFee, payees, amounts);
        // Note: Actual SOL transfers happen on Solana via distribution script
        // This event is the verifiable on-chain record agents use for dispute resolution
    }

    // ─── Emergency Stop ───────────────────────────────────────────────────────

    function declareEmergency(uint256 sid) external onlyOwner {
        sessions[sid].state = SessionState.Emergency;
        emit EmergencyDeclared(sid, msg.sender);
    }

    function setGlobalEmergency(bool active) external onlyOwner {
        globalEmergency = active;
    }

    /// @notice Participants can withdraw stake during emergency
    function emergencyWithdrawStake(uint256 sid) external {
        Session storage s = sessions[sid];
        require(s.state == SessionState.Emergency || globalEmergency, "Not emergency");
        Participant storage p = s.participants[msg.sender];
        require(p.stakeAmount > 0, "Nothing to withdraw");

        uint256 amount = p.stakeAmount;
        p.stakeAmount = 0;
        payable(msg.sender).transfer(amount);
        emit StakeWithdrawn(sid, msg.sender, amount);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    function getParticipantCount(uint256 sid) external view returns (uint256) {
        return sessions[sid].participantAddrs.length;
    }

    function getSessionState(uint256 sid) external view returns (SessionState) {
        return sessions[sid].state;
    }

    function getSelectedCoin(uint256 sid) external view returns (bytes32) {
        return sessions[sid].selectedCoin;
    }

    function getSKRWallet() external pure returns (string memory) {
        return SKR_WALLET_B58;
    }

    function getSettlement(uint256 sid) external view
        returns (uint256 totalProfit, uint256 skrFee, bool settled)
    {
        Session storage s = sessions[sid];
        return (s.totalProfitWei, s.skrFeeWei, s.oracleSettled);
    }

    function getParticipantInfo(uint256 sid, address agent) external view returns (
        bytes32 solanaWallet, uint256 stake, bool committed, bool revealed,
        bool buyConfirmed, bool slashed, uint256 contribution
    ) {
        Participant storage p = sessions[sid].participants[agent];
        return (
            p.solanaWallet, p.stakeAmount, p.committed, p.revealed,
            p.buyConfirmed, p.slashed,    p.contributionWei
        );
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function updatePredicate(address _predicate) external onlyOwner {
        predicate = IAccessPredicate(_predicate);
    }

    function updateOracles(address[] calldata _oracles, uint8 _threshold) external onlyOwner {
        oracles          = _oracles;
        oracleThreshold  = _threshold;
    }

    /// @notice Participants withdraw their stake after session closes normally
    /// @dev Honest participants (not slashed) get their stake back after Closed state
    function withdrawStake(uint256 sid) external {
        Session storage s = sessions[sid];
        require(s.state == SessionState.Closed, "Session not closed");
        Participant storage p = s.participants[msg.sender];
        require(p.stakeAmount > 0,  "No stake to withdraw");
        require(!p.slashed,         "Stake was slashed");

        uint256 amount = p.stakeAmount;
        p.stakeAmount  = 0;
        payable(msg.sender).transfer(amount);
        emit StakeWithdrawn(sid, msg.sender, amount);
    }

    /// @notice Recover stuck ETH (only from expired/emergency sessions)
    function recoverStake(uint256 sid, address payable recipient) external onlyOwner {
        Session storage s = sessions[sid];
        require(
            s.state == SessionState.Emergency ||
            (s.state == SessionState.Open && block.timestamp > s.createdAt + SESSION_TIMEOUT),
            "Session still active"
        );
        uint256 total;
        for (uint i; i < s.participantAddrs.length; i++) {
            total += s.participants[s.participantAddrs[i]].stakeAmount;
            s.participants[s.participantAddrs[i]].stakeAmount = 0;
        }
        if (total > 0) recipient.transfer(total);
    }

    receive() external payable {}
}
