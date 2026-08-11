// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Solang on Solana does not support OpenZeppelin imports directly.
// We inline minimal required interfaces and ReentrancyGuard logic.

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// Minimal ReentrancyGuard for Solana (single-threaded runtime, but kept for compatibility)
contract ReentrancyGuard {
    uint256 private _status;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract SecureNFTStaking is ReentrancyGuard {
    IERC721 public nftCollection;

    bool public isPaused;
    uint256 public constant MAX_BATCH_LIMIT = 50;

    mapping(uint256 => address) public stakedBy;
    mapping(address => uint256[]) private _userStakedTokens;
    mapping(address => mapping(uint256 => uint256)) private _tokenIndex;

    mapping(uint256 => uint256) public lastStakedAt;
    mapping(uint256 => uint256) public lastUnstakedAt;

    struct TimeElapsed {
        uint256 daysElapsed;
        uint256 hoursElapsed;
        uint256 minutesElapsed;
        uint256 secondsElapsed;
    }

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event Recovered(address indexed to, uint256 tokenId);
    event RecoveredBatch(address indexed to, uint256 count);
    event ForceRegistered(address indexed user, uint256 tokenId);
    event ForceRegisteredBatch(address indexed user, uint256 count);
    event UnstakedBatch(address indexed user, uint256 count);
    event StakedBatch(address indexed user, uint256 count);
    event Paused();
    event Unpaused();

    address private _owner;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier whenPaused() {
        require(isPaused, "Contract not paused");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Contract paused");
        _;
    }

    // On Solana, msg.sender is available via Solang's tx.origin or msg.sender.
    // We use msg.sender directly as Solang supports it for Solana.
    constructor(address _nftCollection) {
        require(_nftCollection != address(0), "Invalid collection address");
        nftCollection = IERC721(_nftCollection);
        _owner = msg.sender;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        // IERC721Receiver.onERC721Received.selector is 0x150b7a02
        return bytes4(0x150b7a02);
    }

    function pause() external onlyOwner whenNotPaused {
        isPaused = true;
        emit Paused();
    }

    function unpause() external onlyOwner whenPaused {
        isPaused = false;
        emit Unpaused();
    }

    function batchStake(uint256[] calldata tokenIds)
        external
        nonReentrant
        whenNotPaused
        returns (bool[] memory successList)
    {
        require(tokenIds.length <= MAX_BATCH_LIMIT, "Batch too large");
        address user = msg.sender;
        successList = new bool[](tokenIds.length);
        uint256 stakedCount = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (_tryStake(user, tokenId)) {
                successList[i] = true;
                stakedCount++;
            } else {
                successList[i] = false;
            }
        }

        emit StakedBatch(user, stakedCount);
    }

    function _tryStake(address user, uint256 tokenId) internal returns (bool) {
        if (nftCollection.ownerOf(tokenId) != user) {
            return false;
        }
        if (
            nftCollection.getApproved(tokenId) != address(this) &&
            !nftCollection.isApprovedForAll(user, address(this))
        ) {
            return false;
        }
        if (stakedBy[tokenId] != address(0)) {
            return false;
        }

        nftCollection.safeTransferFrom(user, address(this), tokenId);
        _addStake(user, tokenId);
        return true;
    }

    function _attemptStake(address user, uint256 tokenId) external {
        require(msg.sender == address(this), "Unauthorized");
        require(nftCollection.ownerOf(tokenId) == user, "Not token owner");
        require(
            nftCollection.getApproved(tokenId) == address(this) ||
                nftCollection.isApprovedForAll(user, address(this)),
            "Not approved"
        );
        require(stakedBy[tokenId] == address(0), "Already staked");

        nftCollection.safeTransferFrom(user, address(this), tokenId);
        _addStake(user, tokenId);
    }

    function forceBatchRegisterStake(uint256[] calldata tokenIds, address user)
        external
        onlyOwner
        whenPaused
    {
        require(user != address(0), "Invalid user");
        require(tokenIds.length <= MAX_BATCH_LIMIT, "Batch too large");
        uint256 registeredCount = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (
                stakedBy[tokenId] == address(0) &&
                nftCollection.ownerOf(tokenId) == address(this)
            ) {
                _addStake(user, tokenId);
                emit ForceRegistered(user, tokenId);
                registeredCount++;
            }
        }

        emit ForceRegisteredBatch(user, registeredCount);
    }

    function batchUnstake(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length <= MAX_BATCH_LIMIT, "Batch too large");
        address user = msg.sender;
        uint256 unstakedCount = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (stakedBy[tokenId] == user) {
                delete stakedBy[tokenId];
                _removeStake(user, tokenId);
                nftCollection.safeTransferFrom(address(this), user, tokenId);
                emit Unstaked(user, tokenId);
                unstakedCount++;
            }
        }

        emit UnstakedBatch(user, unstakedCount);
    }

    function _addStake(address user, uint256 tokenId) internal {
        require(stakedBy[tokenId] == address(0), "Token already staked");

        stakedBy[tokenId] = user;
        _userStakedTokens[user].push(tokenId);
        _tokenIndex[user][tokenId] = _userStakedTokens[user].length - 1;
        lastStakedAt[tokenId] = block.timestamp;

        emit Staked(user, tokenId);
    }

    function _removeStake(address user, uint256 tokenId) internal {
        uint256[] storage userTokens = _userStakedTokens[user];
        uint256 index = _tokenIndex[user][tokenId];

        require(userTokens[index] == tokenId, "Index corruption");

        if (index != userTokens.length - 1) {
            uint256 lastTokenId = userTokens[userTokens.length - 1];
            userTokens[index] = lastTokenId;
            _tokenIndex[user][lastTokenId] = index;
        }

        userTokens.pop();
        delete _tokenIndex[user][tokenId];

        lastUnstakedAt[tokenId] = block.timestamp;
    }

    function adminRecover(uint256 tokenId, address to) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(
            nftCollection.ownerOf(tokenId) == address(this),
            "Token not in contract"
        );

        if (stakedBy[tokenId] != address(0)) {
            _removeStake(stakedBy[tokenId], tokenId);
            delete stakedBy[tokenId];
        }

        nftCollection.safeTransferFrom(address(this), to, tokenId);
        emit Recovered(to, tokenId);
    }

    function getUserStakedTokens(address user)
        external
        view
        returns (uint256[] memory)
    {
        return _userStakedTokens[user];
    }

    function getStakeTimestamps(uint256 tokenId)
        external
        view
        returns (uint256 stakedAt, uint256 unstakedAt)
    {
        stakedAt = lastStakedAt[tokenId];
        unstakedAt = lastUnstakedAt[tokenId];
    }

    function getHumanReadableDurations(uint256 tokenId)
        external
        view
        returns (TimeElapsed memory sinceStaked, TimeElapsed memory sinceUnstaked)
    {
        sinceStaked = _getElapsed(lastStakedAt[tokenId]);
        sinceUnstaked = _getElapsed(lastUnstakedAt[tokenId]);
    }

    function _getElapsed(uint256 fromTimestamp) internal view returns (TimeElapsed memory) {
        if (fromTimestamp == 0 || fromTimestamp > block.timestamp) {
            return TimeElapsed(0, 0, 0, 0);
        }

        uint256 elapsed = block.timestamp - fromTimestamp;
        uint256 daysElapsed = elapsed / 1 days;
        elapsed %= 1 days;
        uint256 hoursElapsed = elapsed / 1 hours;
        elapsed %= 1 hours;
        uint256 minutesElapsed = elapsed / 1 minutes;
        uint256 secondsElapsed = elapsed % 1 minutes;

        return TimeElapsed(daysElapsed, hoursElapsed, minutesElapsed, secondsElapsed);
    }
}