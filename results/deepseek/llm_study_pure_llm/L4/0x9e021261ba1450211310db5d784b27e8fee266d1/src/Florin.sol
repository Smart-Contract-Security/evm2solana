// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract Florin is ERC721Votes, Ownable2Step {
    IERC721 public immutable FLORENTINES;

    uint256 public nextFlorinId = 1;
    uint256 public currentRound = 1;

    mapping(uint256 florinId => uint256 florentineId) public parentOf;
    mapping(uint256 florinId => uint256 round) public roundOf;
    mapping(uint256 florentineId => mapping(uint256 round => bool credited))
        public florentineClaimedInRound;

    mapping(uint256 florentineId => uint256[] florinIds) florinsOfFlorentine;
    mapping(address owner => uint256[] florinIds) florinsOfOwner;

    function getFlorinsOfFlorentine(uint256 florentineId) external view returns (uint256[] memory) {
        return florinsOfFlorentine[florentineId];
    }

    function getFlorinsOfOwner(address owner) external view returns (uint256[] memory) {
        return florinsOfOwner[owner];
    }

    string public baseURI;
    address public electionContract;
    uint128 public nominationBurnAmount;
    bool public electionActive;

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

    event FlorinReunited(
        uint256 indexed florinId,
        uint256 indexed florentineId,
        address indexed newOwner
    );

    event FlorinBurned(uint256 indexed florinId, uint256 indexed florentineId, address indexed burner);

    event VoteBurnSkipped(uint256 indexed florinId, address indexed voter);

    event FlorinBurnedForVote(uint256 indexed florinId, address indexed voter);

    event BatchVoteBurn(address indexed voter, uint256[] florinIds);

    event NominationBurn(address indexed nominator, uint256 burnedCount);

    event SingleNominationBurn(address indexed nominator, uint256 indexed florinId);

    event NominationBurnAmountSet(uint256 newAmount);

    event BurnAllCompleted(uint256 indexed start, uint256 indexed end, uint256 burnedCount);

    event AirdropSkipped(
        address indexed intendedRecipient,
        address indexed currentOwner,
        uint256 indexed florentineId,
        uint256 round
    );

    event AirdropDuplicate(
        address indexed intendedRecipient,
        uint256 indexed florentineId,
        uint256 indexed round
    );

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

    constructor(address florentinesAddress)
        ERC721("The Florins", "FLRN")
        EIP712("The Florins", "1")
        Ownable(msg.sender)
    {
        if (florentinesAddress == address(0)) revert ZeroAddress();
        FLORENTINES = IERC721(florentinesAddress);
    }

    function advanceRound() external onlyOwner {
        currentRound += 1;
        emit RoundAdvanced(currentRound);
    }

    function setBaseURI(string calldata cid) external onlyOwner {
        baseURI = cid;
        emit BaseUriUpdated(cid);
    }

    function setElectionContract(address election) external onlyOwner {
        if (electionActive) revert ElectionIsActive();
        if (election == address(0)) revert ZeroAddress();
        electionContract = election;
        emit ElectionContractSet(election);
    }

    function setElectionActive(bool active) external onlyOwner {
        electionActive = active;
        emit ElectionActiveSet(active);
    }

    function setNominationBurnAmount(uint128 amount) external onlyOwner {
        if (electionActive) revert ElectionIsActive();
        nominationBurnAmount = amount;
        emit NominationBurnAmountSet(amount);
    }

    function burnForVote(uint256[] calldata florinIds, address voter) external returns (uint256 burnedCount) {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256[] memory burned = new uint256[](florinIds.length);

        for (uint256 i = 0; i < florinIds.length; ) {
            uint256 fid = florinIds[i];
            if (ownerOf(fid) != voter) revert NotVoterOwned();
            uint256 parentFId = parentOf[fid];

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

        assembly { mstore(burned, burnedCount) }
        emit BatchVoteBurn(voter, burned);

        return burnedCount;
    }

    function burnAllToNominate(address nominator) external {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256[] storage florinIds = florinsOfOwner[nominator];
        uint256 burnedCount = 0;

        while (florinIds.length > 0) {
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

        if (burnedCount == 0) revert NoFlorinsBurned();
        emit NominationBurn(nominator, burnedCount);
    }

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

    function burnOneToNominate(address nominator, uint256 florinId) external {
        if (msg.sender != electionContract) revert NotElectionContract();
        if (ownerOf(florinId) != nominator) revert NotVoterOwned();

        _burn(florinId);
        emit SingleNominationBurn(nominator, florinId);
    }

    function burnAnyOneToNominate(address nominator) external {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256[] storage florinIds = florinsOfOwner[nominator];

        while (florinIds.length > 0) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                emit SingleNominationBurn(nominator, fid);
                return;
            }

            florinIds.pop();

            if (florinIds.length >= lenBefore) revert NoProgress();
        }

        revert NoFlorinsBurned();
    }

    function burnManyToNominate(address nominator) external {
        if (msg.sender != electionContract) revert NotElectionContract();

        uint256 target = nominationBurnAmount;
        if (target == 0) revert NoFlorinsBurned();

        uint256[] storage florinIds = florinsOfOwner[nominator];
        uint256 burnedCount = 0;

        while (florinIds.length > 0) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                unchecked { burnedCount++; }

                if (burnedCount >= target) {
                    emit NominationBurn(nominator, burnedCount);
                    return;
                }
            } else {
                florinIds.pop();
            }

            if (florinIds.length >= lenBefore) revert NoProgress();
        }

        if (burnedCount < target) revert NoFlorinsBurned();
        emit NominationBurn(nominator, burnedCount);
    }

    function airdrop(
        address[] calldata recipients,
        uint256[] calldata florentineIds
    ) external onlyOwner {
        if (recipients.length != florentineIds.length) revert LengthMismatch();

        uint256 round = currentRound;
        for (uint256 i = 0; i < recipients.length; ) {
            uint256 fId = florentineIds[i];
            address intended = recipients[i];

            if (florentineClaimedInRound[fId][round]) {
                emit AirdropDuplicate(intended, fId, round);
                unchecked { i++; }
                continue;
            }

            (bool ok, address currentOwner) = _parentOwnerOf(fId);
            if (!ok) {
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
            emit AirdropSkipped(recipient, address(0), florentineId, round);
            return false;
        }
    }

    function _mintFromSelfCall(address to, uint256 tokenId) external {
        if (msg.sender != address(this)) revert OnlyInternal();
        _mint(to, tokenId);
    }

    function reuniteIfOrphaned(uint256 florinId) external {
        _reuniteIfOrphaned(florinId);
    }

    function reuniteIfOrphanedBatch(uint256[] calldata florinIds) external {
        for (uint256 i = 0; i < florinIds.length; ) {
            uint256 florinId = florinIds[i];

            if (_ownerOf(florinId) == address(0)) {
                unchecked { i++; }
                continue;
            }

            _tryReunite(florinId);
            unchecked { i++; }
        }
    }

    function reuniteIfOrphanedByFlorentinePaginated(
        uint256 florentineId,
        uint256 offset,
        uint256 limit
    ) external {
        uint256[] storage children = florinsOfFlorentine[florentineId];
        if (children.length == 0) return;
        if (offset >= children.length) revert BadRange();

        uint256 end = limit == 0 ? children.length : (offset + limit > children.length ? children.length : offset + limit);

        for (uint256 i = offset; i < end; ) {
            _tryReunite(children[i]);
            unchecked { i++; }
        }
    }

    function reuniteIfOrphanedByFlorentine(uint256 florentineId) external {
        this.reuniteIfOrphanedByFlorentinePaginated(florentineId, 0, 0);
    }

    function reuniteIfOrphanedRange(uint256 start, uint256 end) external {
        if (start == 0 || end == 0 || start > end || end > nextFlorinId - 1)
            revert BadRange();

        for (uint256 florinId = start; florinId <= end; ) {
            if (_ownerOf(florinId) == address(0)) {
                unchecked { florinId++; }
                continue;
            }

            _tryReunite(florinId);
            unchecked { florinId++; }
        }
    }

    function _tryReunite(uint256 florinId) internal {
        if (_ownerOf(florinId) == address(0)) return;

        uint256 parentFId = parentOf[florinId];
        address florinHolder = ownerOf(florinId);

        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) {
            _burn(florinId);
            emit FlorinBurned(florinId, parentFId, address(0));
            return;
        }

        if (parentOwner != florinHolder) {
            _transfer(florinHolder, parentOwner, florinId);
            emit FlorinReunited(florinId, parentFId, parentOwner);
        }
    }

    function _reuniteIfOrphaned(uint256 florinId) internal {
        address florinHolder = ownerOf(florinId);
        uint256 parentFId = parentOf[florinId];

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

    function burn(uint256 florinId) external onlyOwner {
        _burn(florinId);
        emit FlorinBurned(florinId, parentOf[florinId], msg.sender);
    }

    function burnAll(uint256 start, uint256 end) external onlyOwner {
        if (start == 0 || end == 0 || start > end || end > nextFlorinId - 1)
            revert BadRange();

        uint256 burned = 0;
        for (uint256 fid = start; fid <= end; ) {
            if (_ownerOf(fid) != address(0)) {
                _burn(fid);
                emit FlorinBurned(fid, parentOf[fid], msg.sender);
                unchecked { burned++; }
            }
            unchecked { fid++; }
        }
        emit BurnAllCompleted(start, end, burned);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = super._update(to, tokenId, auth);

        if (from != address(0)) {
            _removeFromOwnerArray(from, tokenId);
        }
        if (to != address(0)) {
            florinsOfOwner[to].push(tokenId);
        }

        if (to != address(0) && delegates(to) == address(0)) {
            _delegate(to, to);
        }

        return from;
    }

    function _removeFromOwnerArray(address owner, uint256 tokenId) internal {
        uint256[] storage arr = florinsOfOwner[owner];
        uint256 len = arr.length;
        if (len == 0) return;

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

    uint256 internal constant PARENT_OWNEROF_GAS = 30_000;

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
            ok := staticcall(
                PARENT_OWNEROF_GAS,
                target,
                add(callData, 0x20),
                mload(callData),
                0x00,
                0x20
            )
            if lt(returndatasize(), 0x20) {
                ok := 0
            }
            returnedWord := mload(0x00)
        }

        if (!ok) return (false, address(0));

        tokenOwner = address(uint160(returnedWord));
        success = true;
    }

    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }

    function approve(address /*operator*/, uint256 /*tokenId*/) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address /*operator*/, bool /*approved*/) public pure override {
        revert Soulbound();
    }

    function locked(uint256 tokenId) external view returns (bool) {
        ownerOf(tokenId);
        return true;
    }

    function supportsInterface(bytes4 id) public view override returns (bool) {
        return id == 0xb45a3c0e || super.supportsInterface(id);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function isOrphaned(uint256 florinId) public view returns (bool) {
        if (_ownerOf(florinId) == address(0)) return false;
        uint256 parentFId = parentOf[florinId];
        address florinHolder = ownerOf(florinId);

        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) return true;

        return parentOwner != florinHolder;
    }

    function canBurnForVote(uint256 florinId, address voter)
        external
        view
        returns (bool burnable)
    {
        if (ownerOf(florinId) != voter) return false;
        if (isOrphaned(florinId)) return false;
        return true;
    }

    function totalMinted() external view returns (uint256) {
        return nextFlorinId - 1;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}