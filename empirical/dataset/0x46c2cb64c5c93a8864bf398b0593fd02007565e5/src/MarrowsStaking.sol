// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MarrowsStaking
/// @notice Custodial staking of MysticMarrows (ERC-721) NFTs against an off-chain Maken Team.
///         The contract takes custody of staked MARROWS, keyed by the Team's raw Firestore ID
///         (`bytes32`, no hashing), enforces a per-team cap, lets only the original staker
///         withdraw, and emits events. It knows nothing about pricing, discounts, or wallet
///         identities — the SaaS reads `stakedCountOf(teamId)` off-chain to apply a credit
///         discount tier. See `web3/CLAUDE.md` §2/§3.
/// @dev Immutable logic (no proxy). Pause is the only emergency lever and gates *new* stakes
///      only — `unstake` is never pausable and never blockable by the owner (invariant 1).
contract MarrowsStaking is IERC721Receiver, Ownable, Pausable, ReentrancyGuard {
    /// @notice The only stakeable collection, fixed at deploy (mainnet MARROWS; a mock in tests).
    IERC721 public immutable marrows;

    /// @notice Max NFTs that may be staked per Team, regardless of staker. Owner-settable; never 0.
    uint256 public maxPerTeam;

    /// @notice Original staker of a token, or `address(0)` if the token is not staked here.
    mapping(uint256 tokenId => address staker) public stakerOf;

    /// @notice Team a token is staked against, or `bytes32(0)` if not staked.
    mapping(uint256 tokenId => bytes32 teamId) public teamOf;

    /// @dev Per-team set of staked token IDs, with O(1) swap-and-pop removal.
    mapping(bytes32 teamId => uint256[] tokenIds) private _teamTokens;

    /// @dev Index of a token within its team's `_teamTokens` array (valid only while staked).
    mapping(uint256 tokenId => uint256 index) private _indexInTeam;

    event Staked(bytes32 indexed teamId, uint256 indexed tokenId, address indexed staker);
    event Unstaked(bytes32 indexed teamId, uint256 indexed tokenId, address indexed staker);
    event MaxPerTeamUpdated(uint256 previousMax, uint256 newMax);

    error ZeroAddress();
    error InvalidMaxPerTeam();
    error InvalidTeam();
    error AlreadyStaked(uint256 tokenId);
    error NotStaked(uint256 tokenId);
    error NotStaker(uint256 tokenId, address caller);
    error TeamFull(bytes32 teamId);
    error UnexpectedCollection(address collection);

    /// @param marrows_ The MARROWS ERC-721 collection (a mock in tests, mainnet MARROWS on deploy).
    /// @param maxPerTeam_ Initial per-team cap (must be non-zero; deploy uses 3).
    /// @param owner_ Initial owner (may pause/unpause and set the cap).
    constructor(IERC721 marrows_, uint256 maxPerTeam_, address owner_) Ownable(owner_) {
        if (address(marrows_) == address(0)) revert ZeroAddress();
        if (maxPerTeam_ == 0) revert InvalidMaxPerTeam();
        marrows = marrows_;
        maxPerTeam = maxPerTeam_;
        emit MaxPerTeamUpdated(0, maxPerTeam_);
    }

    // ---------------------------------------------------------------------------------------------
    // Staking
    // ---------------------------------------------------------------------------------------------

    /// @notice Stake a MARROWS token for `teamId`. Caller must have approved this contract on
    ///         MARROWS first; the token is pulled via `transferFrom`.
    /// @dev Path A. Records state before the external transfer (checks-effects-interactions).
    function stake(bytes32 teamId, uint256 tokenId) external whenNotPaused nonReentrant {
        _recordStake(teamId, tokenId, msg.sender);
        marrows.transferFrom(msg.sender, address(this), tokenId);
    }

    /// @notice One-tx stake entry point: `MARROWS.safeTransferFrom(owner, this, tokenId,
    ///         abi.encode(teamId))`. The token is already in custody when this fires, so it only
    ///         records state.
    /// @dev Path B. Reverts unless the caller is the MARROWS collection (invariant 4). `data` must
    ///      be `abi.encode(teamId)`; `from` is the staker.
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata data)
        external
        whenNotPaused
        nonReentrant
        returns (bytes4)
    {
        if (msg.sender != address(marrows)) revert UnexpectedCollection(msg.sender);
        bytes32 teamId = abi.decode(data, (bytes32));
        _recordStake(teamId, tokenId, from);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Shared stake bookkeeping: validate, then record. No external calls here.
    function _recordStake(bytes32 teamId, uint256 tokenId, address staker) private {
        if (staker == address(0)) revert ZeroAddress();
        if (teamId == bytes32(0)) revert InvalidTeam();
        if (stakerOf[tokenId] != address(0)) revert AlreadyStaked(tokenId);

        uint256[] storage tokens = _teamTokens[teamId];
        if (tokens.length >= maxPerTeam) revert TeamFull(teamId);

        stakerOf[tokenId] = staker;
        teamOf[tokenId] = teamId;
        _indexInTeam[tokenId] = tokens.length;
        tokens.push(tokenId);

        emit Staked(teamId, tokenId, staker);
    }

    // ---------------------------------------------------------------------------------------------
    // Unstaking — never pausable, never blockable by the owner (invariant 1)
    // ---------------------------------------------------------------------------------------------

    /// @notice Return a staked token to its original staker. Callable only by that staker.
    /// @dev Not gated by pause. Uses `transferFrom` (not `safeTransferFrom`) so no receiver hook
    ///      can revert or re-enter — the NFT can always be withdrawn. State is cleared before the
    ///      transfer (checks-effects-interactions).
    function unstake(uint256 tokenId) external nonReentrant {
        address staker = stakerOf[tokenId];
        if (staker == address(0)) revert NotStaked(tokenId);
        if (staker != msg.sender) revert NotStaker(tokenId, msg.sender);

        bytes32 teamId = teamOf[tokenId];
        _removeFromTeam(teamId, tokenId);
        delete stakerOf[tokenId];
        delete teamOf[tokenId];

        emit Unstaked(teamId, tokenId, staker);

        marrows.transferFrom(address(this), staker, tokenId);
    }

    /// @dev O(1) swap-and-pop removal of `tokenId` from `teamId`'s set.
    function _removeFromTeam(bytes32 teamId, uint256 tokenId) private {
        uint256[] storage tokens = _teamTokens[teamId];
        uint256 index = _indexInTeam[tokenId];
        uint256 lastIndex = tokens.length - 1;

        if (index != lastIndex) {
            uint256 lastToken = tokens[lastIndex];
            tokens[index] = lastToken;
            _indexInTeam[lastToken] = index;
        }

        tokens.pop();
        delete _indexInTeam[tokenId];
    }

    // ---------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------

    /// @notice Number of MARROWS currently staked for `teamId` (drives the off-chain discount tier).
    function stakedCountOf(bytes32 teamId) external view returns (uint256) {
        return _teamTokens[teamId].length;
    }

    /// @notice The token IDs currently staked for `teamId`.
    function stakedTokensOf(bytes32 teamId) external view returns (uint256[] memory) {
        return _teamTokens[teamId];
    }

    /// @notice Whether `tokenId` is currently staked in this contract.
    function isStaked(uint256 tokenId) external view returns (bool) {
        return stakerOf[tokenId] != address(0);
    }

    // ---------------------------------------------------------------------------------------------
    // Admin (onlyOwner)
    // ---------------------------------------------------------------------------------------------

    /// @notice Update the per-team cap. Lowering it does not evict existing stakes; use `pause()`
    ///         to halt new stakes entirely.
    /// @dev Rejects 0 (`InvalidMaxPerTeam`).
    function setMaxPerTeam(uint256 newMax) external onlyOwner {
        if (newMax == 0) revert InvalidMaxPerTeam();
        uint256 previousMax = maxPerTeam;
        maxPerTeam = newMax;
        emit MaxPerTeamUpdated(previousMax, newMax);
    }

    /// @notice Halt new stakes (both paths). Does not affect `unstake`.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume new stakes.
    function unpause() external onlyOwner {
        _unpause();
    }
}
