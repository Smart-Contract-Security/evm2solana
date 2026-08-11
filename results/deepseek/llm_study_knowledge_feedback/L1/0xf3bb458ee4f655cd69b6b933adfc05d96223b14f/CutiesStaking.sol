// SPDX-License-Identifier: MIT

import 'solana';

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract CutiesStaking {
    address public owner;
    bool public paused;

    struct CollectionConfig {
        bool   enabled;
        uint64 pointsPerHour;
        uint64 meowPerHour;
        uint64 xpPerHour;
        uint16 raffleMultiplier;
    }

    mapping(address => CollectionConfig) public collections;
    address[] public collectionList;
    mapping(address => bool) private _knownCollection;

    struct Stake {
        address owner;
        uint64  stakedAt;
    }

    mapping(address => mapping(uint256 => Stake)) public stakes;
    mapping(address => mapping(address => uint256[])) private _userTokens;
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _userTokenIndex;

    uint64 public constant LOCK_PERIOD = 86400;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PausedSet(bool paused);
    event CollectionConfigured(
        address indexed collection,
        bool    enabled,
        uint64  pointsPerHour,
        uint64  meowPerHour,
        uint64  xpPerHour,
        uint16  raffleMultiplier
    );
    event Staked(address indexed user, address indexed collection, uint256 indexed tokenId, uint64 timestamp);
    event Unstaked(address indexed user, address indexed collection, uint256 indexed tokenId, uint64 timestamp);

    constructor() {
        owner = tx.accounts.dataAccount.key;
        emit OwnershipTransferred(address(0), tx.accounts.dataAccount.key);
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setPaused(bool v) external onlyOwner {
        paused = v;
        emit PausedSet(v);
    }

    function configureCollection(
        address collection,
        bool    enabled,
        uint64  pointsPerHour,
        uint64  meowPerHour,
        uint64  xpPerHour,
        uint16  raffleMultiplier
    ) external onlyOwner {
        require(collection != address(0), "zero collection");
        collections[collection] = CollectionConfig({
            enabled:           enabled,
            pointsPerHour:     pointsPerHour,
            meowPerHour:       meowPerHour,
            xpPerHour:         xpPerHour,
            raffleMultiplier:  raffleMultiplier
        });
        if (!_knownCollection[collection]) {
            _knownCollection[collection] = true;
            collectionList.push(collection);
        }
        emit CollectionConfigured(collection, enabled, pointsPerHour, meowPerHour, xpPerHour, raffleMultiplier);
    }

    function getCollections() external view returns (address[] memory) {
        return collectionList;
    }

    function stake(
        address collection,
        uint256[] calldata tokenIds
    ) external whenNotPaused {
        CollectionConfig memory cfg = collections[collection];
        require(cfg.enabled, "collection disabled");
        require(tokenIds.length > 0, "empty");

        AccountMeta[4] metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: collection, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true})
        ];

        uint64 nowTs = uint64(block.timestamp);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            IERC721(collection).safeTransferFrom{accounts: metas}(tx.accounts.dataAccount.key, address(this), tokenId);
            stakes[collection][tokenId] = Stake({owner: tx.accounts.dataAccount.key, stakedAt: nowTs});
            uint256[] storage list = _userTokens[tx.accounts.dataAccount.key][collection];
            list.push(tokenId);
            _userTokenIndex[tx.accounts.dataAccount.key][collection][tokenId] = list.length;
            emit Staked(tx.accounts.dataAccount.key, collection, tokenId, nowTs);
        }
    }

    function unstake(
        address collection,
        uint256[] calldata tokenIds
    ) external {
        require(tokenIds.length > 0, "empty");

        AccountMeta[4] metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: collection, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true})
        ];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            Stake memory s = stakes[collection][tokenId];
            require(s.owner == tx.accounts.dataAccount.key, "not staker");
            require(uint64(s.stakedAt) + LOCK_PERIOD <= uint64(block.timestamp), "still locked");
            delete stakes[collection][tokenId];
            _removeFromUserList(tx.accounts.dataAccount.key, collection, tokenId);
            IERC721(collection).safeTransferFrom{accounts: metas}(address(this), tx.accounts.dataAccount.key, tokenId);
            emit Unstaked(tx.accounts.dataAccount.key, collection, tokenId, uint64(block.timestamp));
        }
    }

    function rescueERC721(address collection, uint256 tokenId, address to) external onlyOwner {
        require(stakes[collection][tokenId].owner == address(0), "is staked");

        AccountMeta[4] metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: collection, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: to, is_signer: false, is_writable: true})
        ];

        IERC721(collection).safeTransferFrom{accounts: metas}(address(this), to, tokenId);
    }

    function _removeFromUserList(address user, address collection, uint256 tokenId) internal {
        uint256 idx1 = _userTokenIndex[user][collection][tokenId];
        require(idx1 != 0, "not in list");
        uint256 idx = idx1 - 1;
        uint256[] storage list = _userTokens[user][collection];
        uint256 lastIdx = list.length - 1;
        if (idx != lastIdx) {
            uint256 last = list[lastIdx];
            list[idx] = last;
            _userTokenIndex[user][collection][last] = idx + 1;
        }
        list.pop();
        delete _userTokenIndex[user][collection][tokenId];
    }

    function getStakedTokens(address user, address collection) external view returns (uint256[] memory) {
        return _userTokens[user][collection];
    }

    function getStakedDetails(address user, address collection)
        external
        view
        returns (uint256[] memory tokenIds, uint64[] memory stakedAt, uint64[] memory unlockAt)
    {
        uint256[] storage list = _userTokens[user][collection];
        uint256 n = list.length;
        tokenIds = new uint256[](n);
        stakedAt = new uint64[](n);
        unlockAt = new uint64[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 tid = list[i];
            Stake memory s = stakes[collection][tid];
            tokenIds[i] = tid;
            stakedAt[i] = s.stakedAt;
            unlockAt[i] = s.stakedAt + LOCK_PERIOD;
        }
    }

    function pendingRewards(address user, address collection)
        external
        view
        returns (uint256 points, uint256 meow, uint256 xp)
    {
        CollectionConfig memory cfg = collections[collection];
        uint256[] storage list = _userTokens[user][collection];
        uint256 nowTs = block.timestamp;
        for (uint256 i = 0; i < list.length; i++) {
            uint256 elapsed = nowTs - uint256(stakes[collection][list[i]].stakedAt);
            uint256 h = elapsed / 3600;
            points += h * uint256(cfg.pointsPerHour);
            meow   += h * uint256(cfg.meowPerHour);
            xp     += h * uint256(cfg.xpPerHour);
        }
    }

    function stakedCount(address user, address collection) external view returns (uint256) {
        return _userTokens[user][collection].length;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return 0x150b7a02;
    }
}