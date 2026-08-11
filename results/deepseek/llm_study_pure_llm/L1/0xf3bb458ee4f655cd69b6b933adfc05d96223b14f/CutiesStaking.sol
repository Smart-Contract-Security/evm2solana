// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal ERC721 interface (just what we use).
// Declared at file scope - Solidity does not allow nested interfaces.
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

/// @title CutiesStaking
/// @notice Custody-style staking for one or more Cuties ERC721 collections
///         (regular pass, gold pass, etc). Each collection has its own
///         per-hour rates (off-chain accounting units: $meow, points, xp)
///         and a raffle multiplier. Stakers can withdraw a token only after
///         the 24-hour LOCK_PERIOD has elapsed since the most recent stake
///         for that token.
/// @dev    The contract does not mint anything - rates are read off-chain
///         by the backend to credit the user's off-chain balances. The
///         contract is just the source of truth for "who has staked what,
///         since when". Multi-collection support so the gold pass can be
///         configured later without redeploying.
contract CutiesStaking {
    // ---------- ownership ----------
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ---------- pause kill-switch ----------
    bool public paused;
    event PausedSet(bool paused);
    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }
    function setPaused(bool v) external onlyOwner { paused = v; emit PausedSet(v); }

    // ---------- collection config ----------
    struct CollectionConfig {
        bool   enabled;
        uint64 pointsPerHour;
        uint64 meowPerHour;
        uint64 xpPerHour;
        uint16 raffleMultiplier; // integer multiplier (2 for x2, 5 for x5)
    }
    mapping(address => CollectionConfig) public collections;
    address[] public collectionList;
    mapping(address => bool) private _knownCollection;

    event CollectionConfigured(
        address indexed collection,
        bool    enabled,
        uint64  pointsPerHour,
        uint64  meowPerHour,
        uint64  xpPerHour,
        uint16  raffleMultiplier
    );

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

    // ---------- stakes ----------
    struct Stake {
        address owner;
        uint64  stakedAt;
    }
    // collection => tokenId => Stake
    mapping(address => mapping(uint256 => Stake)) public stakes;
    // user => collection => tokenIds (unordered set with swap-and-pop on removal)
    mapping(address => mapping(address => uint256[])) private _userTokens;
    // user => collection => tokenId => (index + 1), 0 = absent
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _userTokenIndex;

    uint256 public constant LOCK_PERIOD = 24 hours;

    event Staked(address indexed user, address indexed collection, uint256 indexed tokenId, uint64 timestamp);
    event Unstaked(address indexed user, address indexed collection, uint256 indexed tokenId, uint64 timestamp);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Stake one or more NFTs from a configured collection. The caller
    ///         must have approved this contract via `setApprovalForAll` (or
    ///         per-token `approve`) on the NFT collection first.
    function stake(address collection, uint256[] calldata tokenIds) external whenNotPaused {
        CollectionConfig memory cfg = collections[collection];
        require(cfg.enabled, "collection disabled");
        require(tokenIds.length > 0, "empty");
        uint64 nowTs = uint64(block.timestamp);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            // Pull the NFT in. Reverts if no allowance or not the owner.
            IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);
            stakes[collection][tokenId] = Stake({owner: msg.sender, stakedAt: nowTs});
            uint256[] storage list = _userTokens[msg.sender][collection];
            list.push(tokenId);
            _userTokenIndex[msg.sender][collection][tokenId] = list.length; // 1-based
            emit Staked(msg.sender, collection, tokenId, nowTs);
        }
    }

    /// @notice Unstake one or more NFTs. Each token must have been staked by
    ///         the caller at least LOCK_PERIOD seconds ago.
    function unstake(address collection, uint256[] calldata tokenIds) external {
        require(tokenIds.length > 0, "empty");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            Stake memory s = stakes[collection][tokenId];
            require(s.owner == msg.sender, "not staker");
            require(uint256(s.stakedAt) + LOCK_PERIOD <= block.timestamp, "still locked");
            delete stakes[collection][tokenId];
            _removeFromUserList(msg.sender, collection, tokenId);
            IERC721(collection).safeTransferFrom(address(this), msg.sender, tokenId);
            emit Unstaked(msg.sender, collection, tokenId, uint64(block.timestamp));
        }
    }

    /// @notice Owner-only rescue: in case an NFT or ETH is stuck (e.g. someone
    ///         sent a token via raw transferFrom bypassing stake()), allows
    ///         pulling it out. Does NOT touch tokens that are currently staked
    ///         on behalf of a real user.
    function rescueERC721(address collection, uint256 tokenId, address to) external onlyOwner {
        require(stakes[collection][tokenId].owner == address(0), "is staked");
        IERC721(collection).safeTransferFrom(address(this), to, tokenId);
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

    // ---------- views ----------
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
            unlockAt[i] = s.stakedAt + uint64(LOCK_PERIOD);
        }
    }

    /// @notice View helper: total pending off-chain rewards across all staked
    ///         tokens of one collection. Frontends sum across collections.
    ///         Returns rounded-down hours * rate (matches the "per hour"
    ///         semantics the UI displays).
    function pendingRewards(address user, address collection)
        external
        view
        returns (uint256 points, uint256 meow, uint256 xp)
    {
        CollectionConfig memory cfg = collections[collection];
        uint256[] storage list = _userTokens[user][collection];
        uint256 nowTs = block.timestamp;
        for (uint256 i = 0; i < list.length; i++) {
            uint256 elapsed = nowTs - stakes[collection][list[i]].stakedAt;
            uint256 h = elapsed / 3600;
            points += h * cfg.pointsPerHour;
            meow   += h * cfg.meowPerHour;
            xp     += h * cfg.xpPerHour;
        }
    }

    function stakedCount(address user, address collection) external view returns (uint256) {
        return _userTokens[user][collection].length;
    }

    // ---------- ERC721 receiver hook (required by safeTransferFrom) ----------
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return 0x150b7a02; // IERC721Receiver.onERC721Received.selector
    }
}