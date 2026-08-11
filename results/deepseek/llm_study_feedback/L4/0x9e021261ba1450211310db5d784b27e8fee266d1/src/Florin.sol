// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

@program_id("F1orin11111111111111111111111111111111111111")
contract Florin {
    IERC721 public immutable FLORENTINES;

    uint256 public nextFlorinId = 1;
    uint256 public currentRound = 1;

    mapping(uint256 florinId => uint256 florentineId) public parentOf;
    mapping(uint256 florinId => uint256 round) public roundOf;
    mapping(uint256 florentineId => mapping(uint256 round => bool credited)) public florentineClaimedInRound;
    mapping(uint256 florentineId => uint256[] florinIds) private _florinsOfFlorentine;
    mapping(address owner => uint256[] florinIds) private _florinsOfOwner;

    function getFlorinsOfFlorentine(uint256 florentineId) external view returns (uint256[] memory) {
        return _florinsOfFlorentine[florentineId];
    }

    function getFlorinsOfOwner(address owner) external view returns (uint256[] memory) {
        return _florinsOfOwner[owner];
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

    address private _owner;

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    constructor(address florentinesAddress) {
        _owner = msg.sender;
        require(florentinesAddress != address(0));
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
        require(!electionActive);
        require(election != address(0));
        electionContract = election;
        emit ElectionContractSet(election);
    }

    function setElectionActive(bool active) external onlyOwner {
        electionActive = active;
        emit ElectionActiveSet(active);
    }

    function setNominationBurnAmount(uint128 amount) external onlyOwner {
        require(!electionActive);
        nominationBurnAmount = amount;
        emit NominationBurnAmountSet(amount);
    }

    function burnForVote(uint256[] calldata florinIds, address voter) external returns (uint256 burnedCount) {
        require(msg.sender == electionContract);

        uint256[] memory burned = new uint256[](florinIds.length);

        for (uint256 i = 0; i < florinIds.length; ) {
            uint256 fid = florinIds[i];
            require(ownerOf(fid) == voter);
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

        // Resize burned array to actual count
        assembly { mstore(burned, burnedCount) }
        emit BatchVoteBurn(voter, burned);

        return burnedCount;
    }

    function burnAllToNominate(address nominator) external {
        require(msg.sender == electionContract);

        uint256[] storage florinIds = _florinsOfOwner[nominator];
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

            require(florinIds.length < lenBefore);
        }

        require(burnedCount > 0);
        emit NominationBurn(nominator, burnedCount);
    }

    function burnAllToNominateBounded(address nominator, uint256 maxBurns)
        external
        returns (bool complete, uint256 burnedCount)
    {
        require(msg.sender == electionContract);
        require(maxBurns > 0);

        uint256[] storage florinIds = _florinsOfOwner[nominator];

        while (florinIds.length > 0 && burnedCount < maxBurns) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                unchecked { burnedCount++; }
            } else {
                florinIds.pop();
            }

            require(florinIds.length < lenBefore);
        }

        complete = (florinIds.length == 0);

        if (burnedCount > 0) {
            emit NominationBurn(nominator, burnedCount);
        }

        return (complete, burnedCount);
    }

    function burnOneToNominate(address nominator, uint256 florinId) external {
        require(msg.sender == electionContract);
        require(ownerOf(florinId) == nominator);

        _burn(florinId);
        emit SingleNominationBurn(nominator, florinId);
    }

    function burnAnyOneToNominate(address nominator) external {
        require(msg.sender == electionContract);

        uint256[] storage florinIds = _florinsOfOwner[nominator];

        while (florinIds.length > 0) {
            uint256 lenBefore = florinIds.length;
            uint256 fid = florinIds[lenBefore - 1];

            if (ownerOf(fid) == nominator) {
                _burn(fid);
                emit SingleNominationBurn(nominator, fid);
                return;
            }

            florinIds.pop();

            require(florinIds.length < lenBefore);
        }

        require(false);
    }

    function burnManyToNominate(address nominator) external {
        require(msg.sender == electionContract);

        uint256 target = nominationBurnAmount;
        require(target > 0);

        uint256[] storage florinIds = _florinsOfOwner[nominator];
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

            require(florinIds.length < lenBefore);
        }

        require(burnedCount >= target);
        emit NominationBurn(nominator, burnedCount);
    }

    function airdrop(
        address[] calldata recipients,
        uint256[] calldata florentineIds
    ) external onlyOwner {
        require(recipients.length == florentineIds.length);

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

        // Simulate try-catch by calling self
        (bool success, ) = address(this).call{accounts: [address(this)]}(abi.encodeWithSignature("_mintFromSelfCall(address,uint256)", recipient, florinId));
        if (success) {
            nextFlorinId++;
            parentOf[florinId] = florentineId;
            roundOf[florinId] = round;
            florentineClaimedInRound[florentineId][round] = true;
            _florinsOfFlorentine[florentineId].push(florinId);

            emit FlorinMinted(florinId, florentineId, recipient, round);
            return true;
        } else {
            emit AirdropSkipped(recipient, address(0), florentineId, round);
            return false;
        }
    }

    function _mintFromSelfCall(address to, uint256 tokenId) external {
        require(msg.sender == address(this));
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
        uint256[] storage children = _florinsOfFlorentine[florentineId];
        if (children.length == 0) return;
        require(offset < children.length);

        uint256 end = limit == 0 ? children.length : (offset + limit > children.length ? children.length : offset + limit);

        for (uint256 i = offset; i < end; ) {
            _tryReunite(children[i]);
            unchecked { i++; }
        }
    }

    function reuniteIfOrphanedByFlorentine(uint256 florentineId) external {
        this.reuniteIfOrphanedByFlorentinePaginated{accounts: [address(this)]}(florentineId, 0, 0);
    }

    function reuniteIfOrphanedRange(uint256 start, uint256 end) external {
        require(start > 0 && end > 0 && start <= end && end <= nextFlorinId - 1);

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

        require(parentOwner != florinHolder);

        _transfer(florinHolder, parentOwner, florinId);
        emit FlorinReunited(florinId, parentFId, parentOwner);
    }

    function burn(uint256 florinId) external onlyOwner {
        _burn(florinId);
        emit FlorinBurned(florinId, parentOf[florinId], msg.sender);
    }

    function burnAll(uint256 start, uint256 end) external onlyOwner {
        require(start > 0 && end > 0 && start <= end && end <= nextFlorinId - 1);

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

    // ERC721 implementation inline
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0));
        return owner;
    }

    function _ownerOf(uint256 tokenId) internal view returns (address) {
        return _owners[tokenId];
    }

    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0));
        return _balances[owner];
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0));
        require(!_exists(tokenId));

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    function _burn(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfer(owner, address(0), tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from);
        require(to != address(0));

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    function _approve(address to, uint256 tokenId) internal {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}
    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function transferFrom(address, address, uint256) public pure {
        require(false);
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure {
        require(false);
    }

    function approve(address, uint256) public pure {
        require(false);
    }

    function setApprovalForAll(address, bool) public pure {
        require(false);
    }

    function locked(uint256 tokenId) external view returns (bool) {
        ownerOf(tokenId);
        return true;
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return id == 0xb45a3c0e || id == 0x80ac58cd || id == 0x5b5e139f || id == 0x01ffc9a7;
    }

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure returns (string memory) {
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

    function _baseURI() internal view returns (string memory) {
        return baseURI;
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

    // Override _update to manage owner arrays
    function _update(address to, uint256 tokenId, address auth)
        internal
        returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0)) {
            _removeFromOwnerArray(from, tokenId);
        }
        if (to != address(0)) {
            _florinsOfOwner[to].push(tokenId);
        }

        return from;
    }

    function _removeFromOwnerArray(address owner, uint256 tokenId) internal {
        uint256[] storage arr = _florinsOfOwner[owner];
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
}