// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title  The Florins
/// @notice A non-transferable ERC-721 with ERC721Votes, minted to participants
///         who customized their Florentine. Each Florin is bound to a specific
///         parent Florentine; if the parent is transferred, anyone can call a
///         `reuniteIfOrphaned*` function to transfer the Florin to the new parent
///         owner. Public transfers remain blocked (unlistable on OpenSea etc.).
/// @dev    Owner-only minting via batch airdrop. Metadata served via IPFS.
///         Implements ERC721Votes for Governor-compatible delegation and
///         checkpointed voting power. Auto-delegates to recipient on mint or
///         reunite if not already delegated. 1-token = 1-vote.
///         Wires to an election contract for vote-and-burn flow.
contract Florin is ERC721Votes, Ownable2Step {
    /* -------------------------------------------------------------------------- */
    /*                                 IMMUTABLES                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The Florentines contract this Florin is anchored to.
    ///         Assumed honest — this contract trusts `FLORENTINES.ownerOf()` as the
    ///         ground truth for parent ownership.
    IERC721 public immutable FLORENTINES;

    /* -------------------------------------------------------------------------- */
    /*                                   STATE                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice The next Florin token ID to be minted. Florin IDs start at 1.
    uint256 public nextFlorinId = 1;

    /// @notice The current campaign round. Starts at 1; incremented via `advanceRound`.
    uint256 public currentRound = 1;

    /// @notice For each Florin, the parent Florentine token ID it was minted for.
    mapping(uint256 florinId => uint256 florentineId) public parentOf;

    /// @notice For each Florin, the round it was minted in.
    mapping(uint256 florinId => uint256 round) public roundOf;

    /// @notice For each Florentine, in each round, whether a Florin has been minted.
    ///         Prevents double-minting on retry.
    mapping(uint256 florentineId => mapping(uint256 round => bool credited))
        public florentineClaimedInRound;

    /// @notice Reverse index: for each Florentine, the list of Florin IDs minted
    ///         for it (across all rounds). Enables `reuniteIfOrphanedByFlorentine`.
    ///         Use `getFlorinsOfFlorentine(florentineId)` to read the full array.
    mapping(uint256 florentineId => uint256[] florinIds) florinsOfFlorentine;

    /// @notice Owner index: for each address, the list of Florin IDs they hold.
    ///         Maintained in `_update` — covers mint, burn, and reunite transfers.
    ///         Enables `burnAllToNominate` without frontend enumeration.
    mapping(address owner => uint256[] florinIds) florinsOfOwner;

    /// @notice Returns all Florin IDs associated with a given Florentine.
    function getFlorinsOfFlorentine(uint256 florentineId) external view returns (uint256[] memory) {
        return florinsOfFlorentine[florentineId];
    }

    /// @notice Returns all Florin IDs currently held by an address. Maintained
    ///         in `_update`; reflects live ownership. Useful for the election
    ///         frontend to display a voter's Florin list, or for the election
    ///         contract to pre-flight `burnAllToNominate` vs the bounded
    ///         variant based on holding size.
    /// @dev    For owners with very large holdings this returns a large array;
    ///         gas-free as a view call but watch RPC response sizes.
    function getFlorinsOfOwner(address owner) external view returns (uint256[] memory) {
        return florinsOfOwner[owner];
    }

    /// @notice The IPFS base URI containing all Florin metadata JSON files.
    ///         Token URI resolves to `{baseURI}{florinId}`.
    string public baseURI;

    /// @notice The registered election contract. Owner may update at any time.
    ///         Only this contract may call `burnForVote`.
    address public electionContract;

    /// @notice The number of Florins required for `burnManyToNominate`.
    ///         Set by owner; 0 disables the function.
    /// @dev    uint128 is sufficient (max supply ~1,401).
    uint128 public nominationBurnAmount;

    /// @notice Defense-in-depth flag indicating an election is currently active.
    ///         When true, `setElectionContract` and `setNominationBurnAmount`
    ///         are locked. Toggled by owner around the election lifecycle.
    ///         Does NOT gate burn functions themselves — those check
    ///         `msg.sender == electionContract` and remain callable so the
    ///         election can run to completion. This flag only protects
    ///         configuration from being changed mid-flight.
    bool public electionActive;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event RoundAdvanced(uint256 indexed newRound);
    event BaseUriUpdated(string cid);
    event ElectionContractSet(address indexed electionContract);
    event ElectionActiveSet(bool active);

    event FlorinMinted(
        uint256 indexed florinId,
        uint256 indexed florentineId,
        address indexed recipient,
        uint256 round
    );

    /// @notice Emitted when a Florin is transferred to the new parent Florentine
    ///         owner via a reunite function.
    event FlorinReunited(
        uint256 indexed florinId,
        uint256 indexed florentineId,
        address indexed newOwner
    );

    /// @notice Emitted when a Florin is burned (owner burn or vote).
    event FlorinBurned(uint256 indexed florinId, uint256 indexed florentineId, address indexed burner);

    /// @notice Emitted when a Florin is skipped during `burnForVote` because
    ///         its parent Florentine is burned or the Florin is orphaned.
    event VoteBurnSkipped(uint256 indexed florinId, address indexed voter);

    /// @notice Emitted when a Florin is burned by the election contract as part
    ///         of the vote-and-burn flow. Indexed for filterable lookups.
    event FlorinBurnedForVote(uint256 indexed florinId, address indexed voter);

    /// @notice Emitted when a batch of Florins is burned for a single vote act.
    ///         Only includes IDs that were actually burned (orphaned ones skipped).
    event BatchVoteBurn(address indexed voter, uint256[] florinIds);

    /// @notice Emitted when Florins are burned for nomination. Summary event —
    ///         no per-Florin emissions (indexers/frontend only need the count).
    event NominationBurn(address indexed nominator, uint256 burnedCount);

    /// @notice Emitted when a single Florin is burned for nomination.
    event SingleNominationBurn(address indexed nominator, uint256 indexed florinId);

    /// @notice Emitted when the configured nomination burn amount is changed.
    event NominationBurnAmountSet(uint256 newAmount);

    /// @notice Emitted when `burnAll` completes a range.
    event BurnAllCompleted(uint256 indexed start, uint256 indexed end, uint256 burnedCount);

    /// @notice Emitted when an airdrop entry is skipped because the intended recipient
    ///         no longer owns the Florentine being credited.
    event AirdropSkipped(
        address indexed intendedRecipient,
        address indexed currentOwner,
        uint256 indexed florentineId,
        uint256 round
    );

    /// @notice Emitted when an airdrop entry is skipped because the Florentine has
    ///         already been credited this round (prevents double-mint on retry).
    event AirdropDuplicate(
        address indexed intendedRecipient,
        uint256 indexed florentineId,
        uint256 indexed round
    );

    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    error Soulbound();
    error StillLinked();
    error LengthMismatch();
    error BadRange();
    error NotElectionContract();
    error NotVoterOwned();
    error NoFlorinsBurned();
    error NoProgress();
    error OnlyInternal();
    error ElectionIsActive();
    error ZeroAddress();

    /* -------------------------------------------------------------------------- */
    /*                                CONSTRUCTOR                                 */
    /* -------------------------------------------------------------------------- */

    constructor(address florentinesAddress)
        ERC721("The Florins", "FLRN")
        EIP712("The Florins", "1")
        Ownable(msg.sender)
    {
        if (florentinesAddress == address(0)) revert ZeroAddress();
        FLORENTINES = IERC721(florentinesAddress);
    }

    /* -------------------------------------------------------------------------- */
    /*                          OWNER: ROUND MANAGEMENT                           */
    /* -------------------------------------------------------------------------- */

    /// @notice Advance to the next round. New mints will be tagged with this round.
    function advanceRound() external onlyOwner {
        currentRound += 1;
        emit RoundAdvanced(currentRound);
    }

    /// @notice Set or update the IPFS base URI for all Florin metadata.
    ///         Metadata files should be at `{baseURI}{florinId}`.
    function setBaseURI(string calldata cid) external onlyOwner {
        baseURI = cid;
        emit BaseUriUpdated(cid);
    }

    /// @notice Update the election contract address. Callable by owner only
    ///         when no election is currently active (electionActive == false).
    /// @dev    WARNING: Do not call this during an active election. Changing the
    ///         registered election contract mid-vote will brick the active
    ///         election — the old contract loses its ability to call
    ///         `burnForVote` / `burn*ToNominate`, and the new contract has
    ///         no awareness of existing tallies. The `electionActive` guard
    ///         enforces this: toggle electionActive off before re-pointing,
    ///         on again when the new election is wired and ready.
    /// @dev    To disable election actions, use `setElectionActive(false)` —
    ///         do NOT set the election contract to address(0). A zero election
    ///         address is rejected as a likely configuration mistake.
    function setElectionContract(address election) external onlyOwner {
        if (electionActive) revert ElectionIsActive();
        if (election == address(0)) revert ZeroAddress();
        electionContract = election;
        emit ElectionContractSet(election);
    }

    /// @notice Toggle the electionActive flag. When true, configuration
    ///         mutators (`setElectionContract`, `setNominationBurnAmount`)
    ///         are locked to prevent mid-election parameter changes.
    /// @dev    Recommended lifecycle:
    ///           1. Deploy election contract
    ///           2. setElectionContract(electionAddress)
    ///           3. setNominationBurnAmount(N) if using burnManyToNominate
    ///           4. setElectionActive(true) — config locked
    ///           5. Run the election
    ///           6. setElectionActive(false) — config unlocked for next round
    /// @param active New value for the electionActive flag.
    function setElectionActive(bool active) external onlyOwner {
        electionActive = active;
        emit ElectionActiveSet(active);
    }

    /// @notice Set the number of Florins required for `burnManyToNominate`.
    ///         Set to 0 to disable. Callable by owner only when no election
    ///         is currently active (electionActive == false).
    /// @dev    WARNING: Do not call this during an active nomination window.
    ///         Changing the required amount mid-election means different
    ///         nominees pay different costs for the same status, breaking
    ///         the election's fairness invariant. The `electionActive` guard
    ///         enforces this: set the value before toggling electionActive on,
    ///         and don't touch it until electionActive is back to false.
    function setNominationBurnAmount(uint128 amount) external onlyOwner {
        if (electionActive) revert ElectionIsActive();
        nominationBurnAmount = amount;
        emit NominationBurnAmountSet(amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                         OWNER: ELECTION BURN                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Burn a batch of Florins as part of the vote-and-burn flow.
    ///         Callable only by the registered election contract.
    ///         Verifies the voter owns each Florin AND its parent Florentine.
    ///         Returns the actual number of Florins burned so the election
    ///         contract can credit votes accurately — submitted array length
    ///         may include skipped orphaned entries.
    /// @dev    Ownership-check asymmetry by design:
    ///         - Voter doesn't own a Florin   → REVERTS (NotVoterOwned). Caller error.
    ///         - Parent Florentine is burned   → SKIPS (emits VoteBurnSkipped).
    ///         - Parent Florentine owned by !voter → SKIPS (emits VoteBurnSkipped).
    ///         Rationale: not owning the Florin is a programming error the caller
    ///         must fix; parent-state mismatches are organic network conditions
    ///         we tolerate to keep batch voting usable.
    /// @param florinIds The Florins to burn.
    /// @param voter The address casting the vote (must own all Florins; parents may be orphaned).
    /// @return burnedCount The number of Florins actually burned (may be < florinIds.length).
    function burnForVote(uint256[] calldata florinIds, address voter) external returns (uint256 burnedCount) {
        if (msg.sender != electionContract) revert NotElectionContract();

        // Collect only IDs that are actually burned (orphaned ones are skipped).
        uint256[] memory burned = new uint256[](florinIds.length);

        for (uint256 i = 0; i < florinIds.length; ) {
            uint256 fid = florinIds[i];
            if (ownerOf(fid) != voter) revert NotVoterOwned();
            uint256 parentFId = parentOf[fid];

            // Parent may be burned or sent to null — skip this Florin.
            // Gas-bounded call protects against malicious/buggy parent contracts.
            (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
            if (!ok) {
                emit VoteBurnSkipped(fid, voter);
                unchecked { i++; }
                continue;
            }

            if (parentOwner != voter) {
                emit VoteBurnSkipped(fid, voter);
                unchecked { i++; }
                continue;
            }

            _burn(fid);
            burned[burnedCount++] = fid;
            emit FlorinBurnedForVote(fid, voter);

            unchecked { i++; }
        }

        // Shrink to actual burned count so event payload is accurate.
        assembly { mstore(burned, burnedCount) }
        emit BatchVoteBurn(voter, burned);

        return burnedCount;
    }

    /// @notice Burn all Florins held by a nominator for a nomination act.
    ///         Callable only by the registered election contract.
    ///         Walks `florinsOfOwner[nominator]` internally — no frontend
    ///         enumeration or stale arrays required. Atomic: burns exactly
    ///         what the nominator holds at execution time.
    ///         Verifies ownership before each burn as a defense against
    ///         index desync. Skips Florins the nominator no longer owns.
    ///         Reverts if no Florins are burned (nominator has none).
    ///         Emits a single summary event.
    /// @dev    For nominators with very large holdings (hundreds of Florins),
    ///         a single tx may approach block gas limits. The election contract
    ///         should consider using `burnAllToNominateBounded` and looping
    ///         off-chain in that case, or pre-flighting the nominator's
    ///         `florinsOfOwner` length to detect when bounded calls are needed.
    /// @param nominator The address nominating (all their Florins are burned).
    function burnAllToNominate(address nominator) external {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256[] storage florinIds = florinsOfOwner[nominator];
        uint256 burnedCount = 0;

        // Burn from the end to avoid index shifting from _removeFromOwnerArray.
        while (florinIds.length > 0) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            // Verify ownership before burn — defense against index desync.
            if (ownerOf(fid) == nominator) {
                _burn(fid);
                unchecked { burnedCount++; }
            } else {
                // Florin no longer belongs to nominator — pop the stale entry. O(1).
                florinIds.pop();
            }

            // Invariant: length must strictly decrease each iteration.
            // Without this, a pathological _removeFromOwnerArray miss would OOG.
            if (florinIds.length >= lenBefore) revert NoProgress();
        }

        if (burnedCount == 0) revert NoFlorinsBurned();
        emit NominationBurn(nominator, burnedCount);
    }

    /// @notice Bounded variant of `burnAllToNominate` for very large nominator
    ///         holdings. Burns up to `maxBurns` Florins from the nominator's
    ///         stack. Returns whether the nominator's holdings are fully drained
    ///         after this call. Does NOT revert on partial completion — the
    ///         election contract is responsible for looping until complete.
    ///         Callable only by the registered election contract.
    /// @dev    Election contract pattern:
    ///         ```
    ///         while (!florin.burnAllToNominateBounded(nominator, BATCH_SIZE)) {
    ///             // loop until fully drained
    ///         }
    ///         ```
    ///         This is escape-hatch hardening for the whale case; small
    ///         nominators should just use `burnAllToNominate` in one shot.
    ///         Unlike `burnAllToNominate`, this does NOT revert when called
    ///         with empty holdings — it returns `complete = true` so the loop
    ///         exits cleanly. The election contract should pre-flight to
    ///         confirm the nominator had Florins to begin with.
    /// @param nominator The address whose Florins are being burned.
    /// @param maxBurns  Maximum Florins to burn in this call (must be > 0).
    /// @return complete True if the nominator's Florin balance is now zero.
    /// @return burnedCount Number of Florins burned in this call.
    function burnAllToNominateBounded(address nominator, uint256 maxBurns)
        external
        returns (bool complete, uint256 burnedCount)
    {
        if (msg.sender != electionContract) revert NotElectionContract();
        if (maxBurns == 0) revert BadRange();

        uint256[] storage florinIds = florinsOfOwner[nominator];

        while (florinIds.length > 0 && burnedCount < maxBurns) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                unchecked { burnedCount++; }
            } else {
                florinIds.pop();
            }

            if (florinIds.length >= lenBefore) revert NoProgress();
        }

        complete = (florinIds.length == 0);

        if (burnedCount > 0) {
            emit NominationBurn(nominator, burnedCount);
        }

        return (complete, burnedCount);
    }

    /// @notice Burn a single Florin held by a nominator for a nomination act.
    ///         Callable only by the registered election contract.
    ///         Verifies ownership before burn. Reverts if the Florin is not
    ///         owned by the nominator.
    ///         Emits a single `SingleNominationBurn` event.
    /// @param nominator The address nominating.
    /// @param florinId  The specific Florin to burn.
    function burnOneToNominate(address nominator, uint256 florinId) external {
        if (msg.sender != electionContract) revert NotElectionContract();
        if (ownerOf(florinId) != nominator) revert NotVoterOwned();

        _burn(florinId);
        emit SingleNominationBurn(nominator, florinId);
    }

    /// @notice Burn any one Florin from the nominator's holdings for a nomination act.
    ///         Callable only by the registered election contract.
    ///         Walks `florinsOfOwner[nominator]` from the back and burns the first
    ///         valid Florin it finds. Cleans up stale entries along the way.
    ///         Reverts if nominator has no Florins.
    ///         Emits a single `SingleNominationBurn` event.
    /// @dev    Named `burnAnyOneToNominate` to disambiguate from
    ///         `burnOneToNominate(address, uint256)` which takes a specific Florin ID.
    /// @param nominator The address nominating (one of their Florins is burned).
    function burnAnyOneToNominate(address nominator) external {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256[] storage florinIds = florinsOfOwner[nominator];

        // Back-to-front iteration matches the pattern in burnAllToNominate
        // and burnManyToNominate. _burn's swap-and-pop becomes a self-swap
        // when removing the last element, so no index-shift bugs.
        while (florinIds.length > 0) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid); // internally removes from florinIds via swap-and-pop
                emit SingleNominationBurn(nominator, fid);
                return;
            }

            // Stale entry — pop O(1).
            florinIds.pop();

            // Invariant: length must strictly decrease each iteration.
            if (florinIds.length >= lenBefore) revert NoProgress();
        }

        revert NoFlorinsBurned();
    }

    /// @notice Burn exactly `nominationBurnAmount` Florins from the nominator's
    ///         holdings for a nomination act. Callable only by the registered
    ///         election contract. Walks `florinsOfOwner[nominator]` and burns
    ///         the first `nominationBurnAmount` valid Florins it finds, cleaning
    ///         up stale entries along the way. Reverts if `nominationBurnAmount`
    ///         is 0 (disabled) or if the nominator has fewer Florins than required.
    ///         Emits a single `NominationBurn` event with the actual burned count.
    /// @param nominator The address nominating.
    function burnManyToNominate(address nominator) external {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256 target = nominationBurnAmount;
        if (target == 0) revert NoFlorinsBurned();

        uint256[] storage florinIds = florinsOfOwner[nominator];
        uint256 burnedCount = 0;

        // _burn already calls _removeFromOwnerArray (swap-and-pop), so we only
        // need to pop in the stale-else branch where _burn is NOT called.
        while (florinIds.length > 0) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid); // internally removes from florinIds via swap-and-pop
                unchecked { burnedCount++; }

                if (burnedCount >= target) {
                    emit NominationBurn(nominator, burnedCount);
                    return;
                }
                // No manual pop needed — _burn already handled it.
            } else {
                // Stale entry — pop O(1).
                florinIds.pop();
            }

            // Invariant: length must strictly decrease each iteration.
            // Without this, a pathological _removeFromOwnerArray miss would OOG.
            if (florinIds.length >= lenBefore) revert NoProgress();
        }

        if (burnedCount < target) revert NoFlorinsBurned();
        emit NominationBurn(nominator, burnedCount);
    }

    /* -------------------------------------------------------------------------- */
    /*                          OWNER: AIRDROP                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Mint Florins to a batch of recipients. Skips entries where the
    ///         recipient doesn't own the Florentine, or where the Florentine
    ///         has already been credited this round.
    /// @param recipients The wallets to mint Florins to.
    /// @param florentineIds The parent Florentine token IDs being credited (pairwise).
    function airdrop(
        address[] calldata recipients,
        uint256[] calldata florentineIds
    ) external onlyOwner {
        if (recipients.length != florentineIds.length) revert LengthMismatch();

        uint256 round = currentRound;
        for (uint256 i = 0; i < recipients.length; ) {
            uint256 fId = florentineIds[i];
            address intended = recipients[i];

            // Skip if this Florentine has already been credited in this round
            if (florentineClaimedInRound[fId][round]) {
                emit AirdropDuplicate(intended, fId, round);
                unchecked { i++; }
                continue;
            }

            // Skip if the recipient no longer owns the Florentine.
            // Gas-bounded call protects against malicious/buggy parent contracts.
            (bool ok, address currentOwner) = _parentOwnerOf(fId);
            if (!ok) {
                // Florentine ownership unreadable — skip this entry
                emit AirdropSkipped(intended, address(0), fId, round);
                unchecked { i++; }
                continue;
            }
            if (currentOwner != intended) {
                emit AirdropSkipped(intended, currentOwner, fId, round);
                unchecked { i++; }
                continue;
            }

            _mintFlorin(intended, fId, round);
            unchecked { i++; }
        }
    }

    function _mintFlorin(
        address recipient,
        uint256 florentineId,
        uint256 round
    ) internal returns (bool minted) {
        uint256 florinId = nextFlorinId;

        try this._mintFromSelfCall(recipient, florinId) {
            nextFlorinId++;
            parentOf[florinId] = florentineId;
            roundOf[florinId] = round;
            florentineClaimedInRound[florentineId][round] = true;
            florinsOfFlorentine[florentineId].push(florinId);

            emit FlorinMinted(florinId, florentineId, recipient, round);
            return true;
        } catch {
            // _mint reverted (e.g. token already exists, or an unexpected
            // low-level failure). Skip this entry rather than aborting the
            // whole airdrop batch. Note: with _mint (not _safeMint) there is
            // no ERC721Receiver hook, so receiver-rejection is NOT a cause here.
            emit AirdropSkipped(recipient, address(0), florentineId, round);
            return false;
        }
    }

    /// @dev External self-call wrapper around `_mint` so that a failed mint
    ///     can be caught by `_mintFlorin` without aborting the whole airdrop
    ///     batch. Only callable by the contract itself.
    /// @dev Uses `_mint`, NOT `_safeMint`: EIP-7702 delegated EOAs carry code,
    ///     so `_safeMint`'s `checkOnERC721Received` would revert for them.
    ///     Florins are soulbound (no transfer path), so the receiver hook
    ///     provides no real safety here anyway.
    function _mintFromSelfCall(address to, uint256 tokenId) external {
        if (msg.sender != address(this)) revert OnlyInternal();
        _mint(to, tokenId);
    }

    /* -------------------------------------------------------------------------- */
    /*                    PERMISSIONLESS: ORPHAN REUNITE                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Reunite a single orphaned Florin with its parent Florentine's new
    ///         owner. Reverts if the Florin is still linked (parent and holder match)
    ///         or already burned.
    function reuniteIfOrphaned(uint256 florinId) external {
        _reuniteIfOrphaned(florinId);
    }

    /// @notice Batch version. Silently skips Florins that are still linked or
    ///         already burned, instead of reverting the whole batch.
    function reuniteIfOrphanedBatch(uint256[] calldata florinIds) external {
        for (uint256 i = 0; i < florinIds.length; ) {
            uint256 florinId = florinIds[i];

            // Skip if already burned
            if (_ownerOf(florinId) == address(0)) {
                unchecked { i++; }
                continue;
            }

            _tryReunite(florinId);
            unchecked { i++; }
        }
    }

    /// @notice Paginated version of `reuniteIfOrphanedByFlorentine`.
    ///         @param florentineId The parent Florentine token ID.
    ///         @param offset       Starting index in the children array.
    ///         @param limit        Max children to process (0 = no limit).
    function reuniteIfOrphanedByFlorentinePaginated(
        uint256 florentineId,
        uint256 offset,
        uint256 limit
    ) external {
        uint256[] storage children = florinsOfFlorentine[florentineId];
        if (children.length == 0) return; // no-op if no children
        if (offset >= children.length) revert BadRange();

        uint256 end = limit == 0 ? children.length : (offset + limit > children.length ? children.length : offset + limit);

        for (uint256 i = offset; i < end; ) {
            _tryReunite(children[i]);
            unchecked { i++; }
        }
    }

    /// @notice Reunite all Florins belonging to a single parent Florentine.
    ///         Uses the `florinsOfFlorentine` reverse index for O(k) lookup
    ///         where k is the number of Florins for that parent.
    ///         Convenience wrapper for `reuniteIfOrphanedByFlorentinePaginated(florentineId, 0, 0)`.
    function reuniteIfOrphanedByFlorentine(uint256 florentineId) external {
        this.reuniteIfOrphanedByFlorentinePaginated(florentineId, 0, 0);
    }

    /// @notice Blind sweep over a range of Florin IDs. Silently skips IDs that
    ///         are still linked, already burned, or out of range.
    ///         Caller is responsible for setting a reasonable range size.
    function reuniteIfOrphanedRange(uint256 start, uint256 end) external {
        if (start == 0 || end == 0 || start > end || end > nextFlorinId - 1)
            revert BadRange();

        for (uint256 florinId = start; florinId <= end; ) {
            // Skip if already burned
            if (_ownerOf(florinId) == address(0)) {
                unchecked { florinId++; }
                continue;
            }

            _tryReunite(florinId);
            unchecked { florinId++; }
        }
    }

    /// @dev Internal: try to reunite a single Florin. Does NOT revert —
    ///         silently skips if still linked or already burned.
    ///         If the parent Florentine is burned/dead, the Florin is auto-burned.
    function _tryReunite(uint256 florinId) internal {
        // Skip if already burned
        if (_ownerOf(florinId) == address(0)) return;

        uint256 parentFId = parentOf[florinId];
        address florinHolder = ownerOf(florinId);

        // Parent may be burned or sent to null — auto-burn the Florin.
        // Gas-bounded call protects against malicious/buggy parent contracts.
        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) {
            // Dead/unreadable parent → burn the Florin too
            _burn(florinId);
            emit FlorinBurned(florinId, parentFId, address(0));
            return;
        }

        // Parent exists but holder disagrees — transfer to new parent owner
        if (parentOwner != florinHolder) {
            _transfer(florinHolder, parentOwner, florinId);
            emit FlorinReunited(florinId, parentFId, parentOwner);
        }
    }

    /// @dev Internal: reunite a single Florin or revert. Used by the
    ///         single-token `reuniteIfOrphaned` public function.
    ///         If the parent Florentine is burned/dead, the Florin is auto-burned.
    function _reuniteIfOrphaned(uint256 florinId) internal {
        address florinHolder = ownerOf(florinId); // reverts if already burned
        uint256 parentFId = parentOf[florinId];

        // Parent may be burned — auto-burn the Florin too.
        // Gas-bounded call protects against malicious/buggy parent contracts.
        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) {
            _burn(florinId);
            emit FlorinBurned(florinId, parentFId, address(0));
            return;
        }

        if (parentOwner == florinHolder) revert StillLinked();

        _transfer(florinHolder, parentOwner, florinId);
        emit FlorinReunited(florinId, parentFId, parentOwner);
    }

    /* -------------------------------------------------------------------------- */
    /*                              BURN                                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Owner-only burn. Destroys a Florin permanently (emergency use only).
    function burn(uint256 florinId) external onlyOwner {
        _burn(florinId);
        emit FlorinBurned(florinId, parentOf[florinId], msg.sender);
    }

    /// @notice Nuclear option: burn all existing Florins. Iterates from `start`
    ///         to `end` (inclusive), burning any that are still alive. Skips
    ///         already-burned tokens. Safe to re-call after a gas revert —
    ///         already-burned entries become no-ops.
    /// @dev    Caller should set a reasonable range to stay within block gas limits.
    ///         ERC721Votes checkpoints make each burn expensive (~60k gas).
    ///         Typical batch: 10–20 tokens per tx depending on state.
    /// @param start First Florin ID to consider (usually 1).
    /// @param end   Last Florin ID to consider (use `totalMinted()` for all).
    function burnAll(uint256 start, uint256 end) external onlyOwner {
        if (start == 0 || end == 0 || start > end || end > nextFlorinId - 1)
            revert BadRange();

        uint256 burned = 0;
        for (uint256 fid = start; fid <= end; ) {
            // Skip already burned
            if (_ownerOf(fid) != address(0)) {
                _burn(fid);
                emit FlorinBurned(fid, parentOf[fid], msg.sender);
                unchecked { burned++; }
            }
            unchecked { fid++; }
        }
        emit BurnAllCompleted(start, end, burned);
    }

    /* -------------------------------------------------------------------------- */
    /*                       ERC721VOTES (AUTO-DELEGATE)                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Auto-delegation on any transfer to a new holder.
    ///     1. super._update writes ownership + checkpoints (ERC721Votes).
    ///     2. Maintain `florinsOfOwner` index: push on mint, swap-and-pop on burn,
    ///        move on reunite.
    ///     3. Auto-delegate to recipient if they have no existing delegation.
    ///     This covers mint (from == 0), burn (to == 0), and reunite transfers.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = super._update(to, tokenId, auth);

        // Maintain owner index.
        if (from != address(0)) {
            _removeFromOwnerArray(from, tokenId);
        }
        if (to != address(0)) {
            florinsOfOwner[to].push(tokenId);
        }

        // Auto-delegate to recipient if they have no existing delegation.
        // Applies on mint AND on reunite — ensures voting power follows the token.
        if (to != address(0) && delegates(to) == address(0)) {
            _delegate(to, to);
        }

        return from;
    }

    /// @dev Swap-and-pop removal from an owner's Florin array. O(1).
    function _removeFromOwnerArray(address owner, uint256 tokenId) internal {
        uint256[] storage arr = florinsOfOwner[owner];
        uint256 len = arr.length;
        if (len == 0) return; // defensive — should never happen

        // Find the token ID and swap with last element.
        for (uint256 i = 0; i < len; ) {
            if (arr[i] == tokenId) {
                uint256 lastIdx = len - 1;
                arr[i] = arr[lastIdx];
                arr.pop();
                return;
            }
            unchecked { i++; }
        }
    }

    /// @notice Gas cap for external `FLORENTINES.ownerOf(...)` lookups.
    ///         A well-behaved ERC-721 ownerOf is ~2-3k gas; the cap is set
    ///         generously to leave headroom for cold storage reads and
    ///         well-behaved proxy patterns, while still bounding griefing
    ///         from a malicious or buggy Florentines implementation.
    /// @dev    Solidity's `try`/`catch` doesn't support gas stipends directly,
    ///         so this is implemented via low-level staticcall.
    uint256 internal constant PARENT_OWNEROF_GAS = 30_000;

    /// @dev Gas-bounded read of `FLORENTINES.ownerOf(tokenId)`.
    ///      Returns (success, owner). Failure cases all surface as
    ///      `success = false` so callers can apply their own policy:
    ///        - the call reverts
    ///        - the call OOGs within PARENT_OWNEROF_GAS
    ///        - the return data is shorter than 32 bytes (malformed)
    ///        - the target address has no contract code
    ///      Callers decide whether to skip or treat as a sentinel value.
    /// @param tokenId The Florentines token ID to look up.
    /// @return success True if the call returned an address cleanly.
    /// @return tokenOwner The returned owner address (only valid if success).
    function _parentOwnerOf(uint256 tokenId)
        internal
        view
        returns (bool success, address tokenOwner)
    {
        bytes memory callData = abi.encodeWithSelector(IERC721.ownerOf.selector, tokenId);
        address target = address(FLORENTINES);

        bool ok;
        uint256 returnedWord;

        assembly {
            // staticcall(gas, to, argsOffset, argsSize, retOffset, retSize)
            // Write the returned word directly into scratch space at 0x00.
            // ABI guarantees the address is left-padded to 32 bytes.
            ok := staticcall(
                PARENT_OWNEROF_GAS,
                target,
                add(callData, 0x20),
                mload(callData),
                0x00,
                0x20
            )
            // If returndatasize < 32, the value at 0x00 may be partial/zero.
            // Use the actual returned size as part of the gate.
            if lt(returndatasize(), 0x20) {
                ok := 0
            }
            returnedWord := mload(0x00)
        }

        if (!ok) return (false, address(0));

        // Cast the lower 160 bits to address. The ABI guarantees the upper
        // 96 bits are zero for a well-formed ownerOf return.
        tokenOwner = address(uint160(returnedWord));
        success = true;
    }

    /// @dev External transfers are blocked — only contract-initiated internal
    ///     transfers (via _transfer in reunite functions) are allowed.
    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }

    /// @dev Approvals are meaningless for non-transferable tokens.
    function approve(address /*operator*/, uint256 /*tokenId*/) public pure override {
        revert Soulbound();
    }

    /// @dev Approvals are meaningless for non-transferable tokens.
    function setApprovalForAll(address /*operator*/, bool /*approved*/) public pure override {
        revert Soulbound();
    }

    /// @notice EIP-5192 interface — signals to wallets/DEXs that all tokens
    ///         are permanently locked (non-transferable). Reverts for
    ///         nonexistent or burned tokens, per EIP-5192 semantics.
    /// @dev    `ownerOf` reverts if the token does not exist; this is the
    ///         existence gate. View (not pure) because it reads ownership state.
    function locked(uint256 tokenId) external view returns (bool) {
        ownerOf(tokenId); // reverts if nonexistent/burned
        return true;
    }

    /// @notice EIP-5192 supportsInterface — marketplaces check this before
    ///         querying `locked()`.
    function supportsInterface(bytes4 id) public view override returns (bool) {
        return id == 0xb45a3c0e || super.supportsInterface(id);
    }

    /* -------------------------------------------------------------------------- */
    /*                              ERC6372 CLOCK                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice ERC-6372 clock — uses block timestamps for checkpoint expiry.
    ///         Cheap to add now, painful to change later if multichain is needed.
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice ERC-6372 clock mode — timestamp-based.
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /* -------------------------------------------------------------------------- */
    /*                                   VIEWS                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Whether a Florin's parent Florentine is owned by someone other
    ///         than the Florin's current holder. Returns false if Florin is burned.
    ///         If the parent Florentine is burned/dead/unreadable, returns true
    ///         (definitely orphaned).
    function isOrphaned(uint256 florinId) public view returns (bool) {
        if (_ownerOf(florinId) == address(0)) return false;
        uint256 parentFId = parentOf[florinId];
        address florinHolder = ownerOf(florinId);

        // Gas-bounded call protects against malicious/buggy parent contracts.
        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) return true; // burned/unreadable parent → orphaned

        return parentOwner != florinHolder;
    }

    /// @notice Check if a Florin would actually burn during `burnForVote`.
    ///         Returns true if the voter owns the Florin AND the parent
    ///         Florentine is not orphaned (i.e. still owned by the voter).
    ///         Returns false if the Florin is not owned by the voter or
    ///         the parent is burned/transferred away (would be skipped).
    ///         Used by election contracts for dry-run validation via `eth_call`.
    /// @param florinId The Florin to check.
    /// @param voter The prospective voter (must match owner).
    /// @return burnable Whether this Florin would burn rather than skip.
    function canBurnForVote(uint256 florinId, address voter)
        external
        view
        returns (bool burnable)
    {
        if (ownerOf(florinId) != voter) return false;
        if (isOrphaned(florinId)) return false;
        return true;
    }

    /// @notice Total Florins minted to date (including burned).
    function totalMinted() external view returns (uint256) {
        return nextFlorinId - 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  METADATA                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the base URI for token metadata. Metadata files are at
    ///         `{_baseURI}{tokenId}` — e.g. ipfs://QmXyZ123/1
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
