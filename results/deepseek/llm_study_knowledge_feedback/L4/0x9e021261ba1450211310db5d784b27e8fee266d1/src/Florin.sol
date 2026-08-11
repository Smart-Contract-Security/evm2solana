// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

@program_id("F1orin11111111111111111111111111111111111111")
contract Florin {
    address public immutable FLORENTINES;

    uint64 public nextFlorinId = 1;
    uint64 public currentRound = 1;

    mapping(uint64 florinId => uint64 florentineId) public parentOf;
    mapping(uint64 florinId => uint64 round) public roundOf;
    mapping(uint64 florentineId => mapping(uint64 round => bool credited)) public florentineClaimedInRound;
    mapping(uint64 florentineId => uint64[] florinIds) florinsOfFlorentine;
    mapping(address owner => uint64[] florinIds) florinsOfOwner;

    function getFlorinsOfFlorentine(uint64 florentineId) external view returns (uint64[] memory) {
        return florinsOfFlorentine[florentineId];
    }

    function getFlorinsOfOwner(address owner) external view returns (uint64[] memory) {
        return florinsOfOwner[owner];
    }

    string public baseURI;
    address public electionContract;
    uint64 public nominationBurnAmount;
    bool public electionActive;

    event RoundAdvanced(uint64 indexed newRound);
    event BaseUriUpdated(string cid);
    event ElectionContractSet(address indexed electionContract);
    event ElectionActiveSet(bool active);

    event FlorinMinted(
        uint64 indexed florinId,
        uint64 indexed florentineId,
        address indexed recipient,
        uint64 round
    );

    event FlorinReunited(
        uint64 indexed florinId,
        uint64 indexed florentineId,
        address indexed newOwner
    );

    event FlorinBurned(uint64 indexed florinId, uint64 indexed florentineId, address indexed burner);

    event VoteBurnSkipped(uint64 indexed florinId, address indexed voter);

    event FlorinBurnedForVote(uint64 indexed florinId, address indexed voter);

    event BatchVoteBurn(address indexed voter, uint64[] florinIds);

    event NominationBurn(address indexed nominator, uint64 burnedCount);

    event SingleNominationBurn(address indexed nominator, uint64 indexed florinId);

    event NominationBurnAmountSet(uint64 newAmount);

    event BurnAllCompleted(uint64 indexed start, uint64 indexed end, uint64 burnedCount);

    event AirdropSkipped(
        address indexed intendedRecipient,
        address indexed currentOwner,
        uint64 indexed florentineId,
        uint64 round
    );

    event AirdropDuplicate(
        address indexed intendedRecipient,
        uint64 indexed florentineId,
        uint64 indexed round
    );

    address private _owner;

    constructor(address florentinesAddress) {
        if (florentinesAddress == address(0)) {
            revert("ZeroAddress");
        }
        FLORENTINES = florentinesAddress;
        _owner = tx.accounts.dataAccount.key;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
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
        if (electionActive) {
            revert("ElectionIsActive");
        }
        if (election == address(0)) {
            revert("ZeroAddress");
        }
        electionContract = election;
        emit ElectionContractSet(election);
    }

    function setElectionActive(bool active) external onlyOwner {
        electionActive = active;
        emit ElectionActiveSet(active);
    }

    function setNominationBurnAmount(uint64 amount) external onlyOwner {
        if (electionActive) {
            revert("ElectionIsActive");
        }
        nominationBurnAmount = amount;
        emit NominationBurnAmountSet(amount);
    }

    function burnForVote(uint64[] calldata florinIds, address voter) external returns (uint64 burnedCount) {
        if (tx.accounts.dataAccount.key != electionContract) {
            revert("NotElectionContract");
        }

        uint64[] memory burned = new uint64[](florinIds.length);

        for (uint64 i = 0; i < florinIds.length; ) {
            uint64 fid = florinIds[i];
            if (ownerOf(fid) != voter) {
                revert("NotVoterOwned");
            }
            uint64 parentFId = parentOf[fid];

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

        emit BatchVoteBurn(voter, burned);

        return burnedCount;
    }

    function burnAllToNominate(address nominator) external {
        if (tx.accounts.dataAccount.key != electionContract) {
            revert("NotElectionContract");
        }

        uint64[] storage florinIds = florinsOfOwner[nominator];
        uint64 burnedCount = 0;

        while (florinIds.length > 0) {
            uint64 lenBefore = uint64(florinIds.length);
            uint64 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                unchecked { burnedCount++; }
            } else {
                florinIds.pop();
            }

            if (florinIds.length >= lenBefore) {
                revert("NoProgress");
            }
        }

        if (burnedCount == 0) {
            revert("NoFlorinsBurned");
        }
        emit NominationBurn(nominator, burnedCount);
    }

    function burnAllToNominateBounded(address nominator, uint64 maxBurns)
        external
        returns (bool complete, uint64 burnedCount)
    {
        if (tx.accounts.dataAccount.key != electionContract) {
            revert("NotElectionContract");
        }
        if (maxBurns == 0) {
            revert("BadRange");
        }

        uint64[] storage florinIds = florinsOfOwner[nominator];

        while (florinIds.length > 0 && burnedCount < maxBurns) {
            uint64 lenBefore = uint64(florinIds.length);
            uint64 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                unchecked { burnedCount++; }
            } else {
                florinIds.pop();
            }

            if (florinIds.length >= lenBefore) {
                revert("NoProgress");
            }
        }

        complete = (florinIds.length == 0);

        if (burnedCount > 0) {
            emit NominationBurn(nominator, burnedCount);
        }

        return (complete, burnedCount);
    }

    function burnOneToNominate(address nominator, uint64 florinId) external {
        if (tx.accounts.dataAccount.key != electionContract) {
            revert("NotElectionContract");
        }
        if (ownerOf(florinId) != nominator) {
            revert("NotVoterOwned");
        }

        _burn(florinId);
        emit SingleNominationBurn(nominator, florinId);
    }

    function burnAnyOneToNominate(address nominator) external {
        if (tx.accounts.dataAccount.key != electionContract) {
            revert("NotElectionContract");
        }

        uint64[] storage florinIds = florinsOfOwner[nominator];

        while (florinIds.length > 0) {
            uint64 lenBefore = uint64(florinIds.length);
            uint64 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                emit SingleNominationBurn(nominator, fid);
                return;
            }

            florinIds.pop();

            if (florinIds.length >= lenBefore) {
                revert("NoProgress");
            }
        }

        revert("NoFlorinsBurned");
    }

    function burnManyToNominate(address nominator) external {
        if (tx.accounts.dataAccount.key != electionContract) {
            revert("NotElectionContract");
        }

        uint64 target = nominationBurnAmount;
        if (target == 0) {
            revert("NoFlorinsBurned");
        }

        uint64[] storage florinIds = florinsOfOwner[nominator];
        uint64 burnedCount = 0;

        while (florinIds.length > 0) {
            uint64 lenBefore = uint64(florinIds.length);
            uint64 fid = florinIds[lenBefore - 1];

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

            if (florinIds.length >= lenBefore) {
                revert("NoProgress");
            }
        }

        if (burnedCount < target) {
            revert("NoFlorinsBurned");
        }
        emit NominationBurn(nominator, burnedCount);
    }

    function airdrop(
        address[] calldata recipients,
        uint64[] calldata florentineIds
    ) external onlyOwner {
        if (recipients.length != florentineIds.length) {
            revert("LengthMismatch");
        }

        uint64 round = currentRound;
        for (uint64 i = 0; i < recipients.length; ) {
            uint64 fId = florentineIds[i];
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
        uint64 florentineId,
        uint64 round
    ) internal returns (bool minted) {
        uint64 florinId = nextFlorinId;

        _mint(recipient, florinId);
        nextFlorinId++;
        parentOf[florinId] = florentineId;
        roundOf[florinId] = round;
        florentineClaimedInRound[florentineId][round] = true;
        florinsOfFlorentine[florentineId].push(florinId);

        emit FlorinMinted(florinId, florentineId, recipient, round);
        return true;
    }

    function reuniteIfOrphaned(uint64 florinId) external {
        _reuniteIfOrphaned(florinId);
    }

    function reuniteIfOrphanedBatch(uint64[] calldata florinIds) external {
        for (uint64 i = 0; i < florinIds.length; ) {
            uint64 florinId = florinIds[i];

            if (_ownerOf(florinId) == address(0)) {
                unchecked { i++; }
                continue;
            }

            _tryReunite(florinId);
            unchecked { i++; }
        }
    }

    function reuniteIfOrphanedByFlorentinePaginated(
        uint64 florentineId,
        uint64 offset,
        uint64 limit
    ) external {
        uint64[] storage children = florinsOfFlorentine[florentineId];
        if (children.length == 0) return;
        if (offset >= children.length) {
            revert("BadRange");
        }

        uint64 end = limit == 0 ? uint64(children.length) : (offset + limit > children.length ? uint64(children.length) : offset + limit);

        for (uint64 i = offset; i < end; ) {
            _tryReunite(children[i]);
            unchecked { i++; }
        }
    }

    function reuniteIfOrphanedByFlorentine(uint64 florentineId) external {
        this.reuniteIfOrphanedByFlorentinePaginated(florentineId, 0, 0);
    }

    function reuniteIfOrphanedRange(uint64 start, uint64 end) external {
        if (start == 0 || end == 0 || start > end || end > nextFlorinId - 1) {
            revert("BadRange");
        }

        for (uint64 florinId = start; florinId <= end; ) {
            if (_ownerOf(florinId) == address(0)) {
                unchecked { florinId++; }
                continue;
            }

            _tryReunite(florinId);
            unchecked { florinId++; }
        }
    }

    function _tryReunite(uint64 florinId) internal {
        if (_ownerOf(florinId) == address(0)) return;

        uint64 parentFId = parentOf[florinId];
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

    function _reuniteIfOrphaned(uint64 florinId) internal {
        address florinHolder = ownerOf(florinId);
        uint64 parentFId = parentOf[florinId];

        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) {
            _burn(florinId);
            emit FlorinBurned(florinId, parentFId, address(0));
            return;
        }

        if (parentOwner == florinHolder) {
            revert("StillLinked");
        }

        _transfer(florinHolder, parentOwner, florinId);
        emit FlorinReunited(florinId, parentFId, parentOwner);
    }

    function burn(uint64 florinId) external onlyOwner {
        _burn(florinId);
        emit FlorinBurned(florinId, parentOf[florinId], tx.accounts.dataAccount.key);
    }

    function burnAll(uint64 start, uint64 end) external onlyOwner {
        if (start == 0 || end == 0 || start > end || end > nextFlorinId - 1) {
            revert("BadRange");
        }

        uint64 burned = 0;
        for (uint64 fid = start; fid <= end; ) {
            if (_ownerOf(fid) != address(0)) {
                _burn(fid);
                emit FlorinBurned(fid, parentOf[fid], tx.accounts.dataAccount.key);
                unchecked { burned++; }
            }
            unchecked { fid++; }
        }
        emit BurnAllCompleted(start, end, burned);
    }

    function _update(address to, uint64 tokenId, address auth)
        internal
        returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0)) {
            _removeFromOwnerArray(from, tokenId);
        }
        if (to != address(0)) {
            florinsOfOwner[to].push(tokenId);
        }

        return from;
    }

    function _removeFromOwnerArray(address ownerAddr, uint64 tokenId) internal {
        uint64[] storage arr = florinsOfOwner[ownerAddr];
        uint64 len = uint64(arr.length);
        if (len == 0) return;

        for (uint64 i = 0; i < len; ) {
            if (arr[i] == tokenId) {
                uint64 lastIdx = len - 1;
                arr[i] = arr[lastIdx];
                arr.pop();
                return;
            }
            unchecked { i++; }
        }
    }

    function _parentOwnerOf(uint64 tokenId)
        internal
        view
        returns (bool success, address tokenOwner)
    {
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: FLORENTINES, is_signer: false, is_writable: false})
        ];

        bytes memory callData = abi.encodeWithSelector(0x6352211e, tokenId);

        (bool ok, bytes memory result) = FLORENTINES.call{accounts: metas}(callData);

        if (!ok || result.length < 32) return (false, address(0));

        tokenOwner = abi.decode(result, (address));
        success = true;
    }

    function transferFrom(address, address, uint64) public pure {
        revert("Soulbound");
    }

    function safeTransferFrom(address, address, uint64, bytes memory) public pure {
        revert("Soulbound");
    }

    function approve(address, uint64) public pure {
        revert("Soulbound");
    }

    function setApprovalForAll(address, bool) public pure {
        revert("Soulbound");
    }

    function locked(uint64 tokenId) external view returns (bool) {
        ownerOf(tokenId);
        return true;
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return id == 0xb45a3c0e || id == 0x80ac58cd || id == 0x5b5e139f || id == 0x01ffc9a7;
    }

    function clock() public view returns (uint64) {
        return uint64(block.timestamp);
    }

    function CLOCK_MODE() public pure returns (string memory) {
        return "mode=timestamp";
    }

    function isOrphaned(uint64 florinId) public view returns (bool) {
        if (_ownerOf(florinId) == address(0)) return false;
        uint64 parentFId = parentOf[florinId];
        address florinHolder = ownerOf(florinId);

        (bool ok, address parentOwner) = _parentOwnerOf(parentFId);
        if (!ok) return true;

        return parentOwner != florinHolder;
    }

    function canBurnForVote(uint64 florinId, address voter)
        external
        view
        returns (bool burnable)
    {
        if (ownerOf(florinId) != voter) return false;
        if (isOrphaned(florinId)) return false;
        return true;
    }

    function totalMinted() external view returns (uint64) {
        return nextFlorinId - 1;
    }

    function _baseURI() internal view returns (string memory) {
        return baseURI;
    }

    // ERC721 core state and functions
    mapping(uint64 => address) private _owners;
    mapping(address => uint64) private _balances;
    mapping(uint64 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    function balanceOf(address ownerAddr) public view returns (uint64) {
        require(ownerAddr != address(0), "ZeroAddress");
        return _balances[ownerAddr];
    }

    function ownerOf(uint64 tokenId) public view returns (address) {
        address ownerAddr = _ownerOf(tokenId);
        require(ownerAddr != address(0), "NonexistentToken");
        return ownerAddr;
    }

    function _ownerOf(uint64 tokenId) internal view returns (address) {
        return _owners[tokenId];
    }

    function _mint(address to, uint64 tokenId) internal {
        require(to != address(0), "ZeroAddress");
        require(_ownerOf(tokenId) == address(0), "AlreadyMinted");

        _balances[to]++;
        _owners[tokenId] = to;

        _update(to, tokenId, address(0));
    }

    function _burn(uint64 tokenId) internal {
        address ownerAddr = _ownerOf(tokenId);
        require(ownerAddr != address(0), "NonexistentToken");

        _update(address(0), tokenId, ownerAddr);

        _balances[ownerAddr]--;
        delete _owners[tokenId];
        delete _tokenApprovals[tokenId];
    }

    function _transfer(address from, address to, uint64 tokenId) internal {
        require(ownerOf(tokenId) == from, "NotOwner");
        require(to != address(0), "ZeroAddress");

        _update(to, tokenId, from);

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
    }

    function getApproved(uint64 tokenId) public view returns (address) {
        require(_ownerOf(tokenId) != address(0), "NonexistentToken");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address ownerAddr, address operator) public view returns (bool) {
        return _operatorApprovals[ownerAddr][operator];
    }

    function tokenURI(uint64 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "NonexistentToken");
        string memory base = _baseURI();
        return bytes(base).length > 0 ? string(abi.encodePacked(base, tokenId)) : "";
    }
}