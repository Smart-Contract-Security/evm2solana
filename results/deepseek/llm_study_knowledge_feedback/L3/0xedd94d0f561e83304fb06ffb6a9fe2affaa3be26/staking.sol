// SPDX-License-Identifier: MIT

import 'solana';

contract SecureNFTStaking {
    address public immutable nftCollection;

    bool public isPaused;
    uint64 public constant MAX_BATCH_LIMIT = 50;

    mapping(uint64 => address) public stakedBy;
    mapping(address => uint64[]) private _userStakedTokens;
    mapping(address => mapping(uint64 => uint64)) private _tokenIndex;

    mapping(uint64 => uint64) public lastStakedAt;
    mapping(uint64 => uint64) public lastUnstakedAt;

    struct TimeElapsed {
        uint64 daysElapsed;
        uint64 hoursElapsed;
        uint64 minutesElapsed;
        uint64 secondsElapsed;
    }

    event Staked(address indexed user, uint64 tokenId);
    event Unstaked(address indexed user, uint64 tokenId);
    event Recovered(address indexed to, uint64 tokenId);
    event RecoveredBatch(address indexed to, uint64 count);
    event ForceRegistered(address indexed user, uint64 tokenId);
    event ForceRegisteredBatch(address indexed user, uint64 count);
    event UnstakedBatch(address indexed user, uint64 count);
    event StakedBatch(address indexed user, uint64 count);
    event Paused();
    event Unpaused();

    address private _owner;

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
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

    modifier nonReentrant() {
        _;
    }

    constructor(address _nftCollection) {
        require(_nftCollection != address(0), "Invalid collection address");
        nftCollection = _nftCollection;
        _owner = tx.accounts.dataAccount.key;
    }

    function onERC721Received(address, address, uint64, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return 0x150b7a02;
    }

    function pause() external onlyOwner whenNotPaused {
        isPaused = true;
        emit Paused();
    }

    function unpause() external onlyOwner whenPaused {
        isPaused = false;
        emit Unpaused();
    }

    function batchStake(uint64[] calldata tokenIds)
        external
        nonReentrant
        whenNotPaused
        returns (bool[] memory successList)
    {
        require(tokenIds.length <= MAX_BATCH_LIMIT, "Batch too large");
        address user = tx.accounts.dataAccount.key;
        successList = new bool[](tokenIds.length);
        uint64 stakedCount = 0;

        for (uint64 i = 0; i < tokenIds.length; i++) {
            uint64 tokenId = tokenIds[i];
            if (_tryStake(user, tokenId)) {
                successList[i] = true;
                stakedCount++;
            } else {
                successList[i] = false;
            }
        }

        emit StakedBatch(user, stakedCount);
    }

    function _tryStake(address user, uint64 tokenId) internal returns (bool) {
        (bool success1, bytes memory result1) = nftCollection.call{accounts: []}(
            abi.encodeWithSignature("ownerOf(uint64)", tokenId)
        );
        require(success1, "ownerOf call failed");
        address tokenOwner = abi.decode(result1, (address));

        (bool success2, bytes memory result2) = nftCollection.call{accounts: []}(
            abi.encodeWithSignature("getApproved(uint64)", tokenId)
        );
        require(success2, "getApproved call failed");
        address approved = abi.decode(result2, (address));

        (bool success3, bytes memory result3) = nftCollection.call{accounts: []}(
            abi.encodeWithSignature("isApprovedForAll(address,address)", user, address(this))
        );
        require(success3, "isApprovedForAll call failed");
        bool isApproved = abi.decode(result3, (bool));

        if (
            tokenOwner == user &&
            (approved == address(this) || isApproved) &&
            stakedBy[tokenId] == address(0)
        ) {
            (bool success4, ) = nftCollection.call{accounts: []}(
                abi.encodeWithSignature("safeTransferFrom(address,address,uint64)", user, address(this), tokenId)
            );
            require(success4, "safeTransferFrom call failed");
            _addStake(user, tokenId);
            return true;
        }
        return false;
    }

    function forceBatchRegisterStake(uint64[] calldata tokenIds, address user)
        external
        onlyOwner
        whenPaused
    {
        require(user != address(0), "Invalid user");
        require(tokenIds.length <= MAX_BATCH_LIMIT, "Batch too large");
        uint64 registeredCount = 0;

        for (uint64 i = 0; i < tokenIds.length; i++) {
            uint64 tokenId = tokenIds[i];
            (bool success, bytes memory result) = nftCollection.call{accounts: []}(
                abi.encodeWithSignature("ownerOf(uint64)", tokenId)
            );
            require(success, "ownerOf call failed");
            address tokenOwner = abi.decode(result, (address));

            if (
                stakedBy[tokenId] == address(0) &&
                tokenOwner == address(this)
            ) {
                _addStake(user, tokenId);
                emit ForceRegistered(user, tokenId);
                registeredCount++;
            }
        }

        emit ForceRegisteredBatch(user, registeredCount);
    }

    function batchUnstake(uint64[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length <= MAX_BATCH_LIMIT, "Batch too large");
        address user = tx.accounts.dataAccount.key;
        uint64 unstakedCount = 0;

        for (uint64 i = 0; i < tokenIds.length; i++) {
            uint64 tokenId = tokenIds[i];
            if (stakedBy[tokenId] == user) {
                delete stakedBy[tokenId];
                _removeStake(user, tokenId);
                (bool success, ) = nftCollection.call{accounts: []}(
                    abi.encodeWithSignature("safeTransferFrom(address,address,uint64)", address(this), user, tokenId)
                );
                require(success, "safeTransferFrom call failed");
                emit Unstaked(user, tokenId);
                unstakedCount++;
            }
        }

        emit UnstakedBatch(user, unstakedCount);
    }

    function _addStake(address user, uint64 tokenId) internal {
        require(stakedBy[tokenId] == address(0), "Token already staked");

        stakedBy[tokenId] = user;
        _userStakedTokens[user].push(tokenId);
        _tokenIndex[user][tokenId] = uint64(_userStakedTokens[user].length - 1);
        lastStakedAt[tokenId] = uint64(block.timestamp);

        emit Staked(user, tokenId);
    }

    function _removeStake(address user, uint64 tokenId) internal {
        uint64[] storage userTokens = _userStakedTokens[user];
        uint64 index = _tokenIndex[user][tokenId];

        require(userTokens[index] == tokenId, "Index corruption");

        if (index != userTokens.length - 1) {
            uint64 lastTokenId = userTokens[userTokens.length - 1];
            userTokens[index] = lastTokenId;
            _tokenIndex[user][lastTokenId] = index;
        }

        userTokens.pop();
        delete _tokenIndex[user][tokenId];

        lastUnstakedAt[tokenId] = uint64(block.timestamp);
    }

    function adminRecover(uint64 tokenId, address to) external onlyOwner {
        require(to != address(0), "Invalid address");
        (bool success, bytes memory result) = nftCollection.call{accounts: []}(
            abi.encodeWithSignature("ownerOf(uint64)", tokenId)
        );
        require(success, "ownerOf call failed");
        address tokenOwner = abi.decode(result, (address));
        require(tokenOwner == address(this), "Token not in contract");

        if (stakedBy[tokenId] != address(0)) {
            _removeStake(stakedBy[tokenId], tokenId);
            delete stakedBy[tokenId];
        }

        (bool success2, ) = nftCollection.call{accounts: []}(
            abi.encodeWithSignature("safeTransferFrom(address,address,uint64)", address(this), to, tokenId)
        );
        require(success2, "safeTransferFrom call failed");
        emit Recovered(to, tokenId);
    }

    function getUserStakedTokens(address user)
        external
        view
        returns (uint64[] memory)
    {
        return _userStakedTokens[user];
    }

    function getStakeTimestamps(uint64 tokenId)
        external
        view
        returns (uint64 stakedAt, uint64 unstakedAt)
    {
        stakedAt = lastStakedAt[tokenId];
        unstakedAt = lastUnstakedAt[tokenId];
    }

    function getHumanReadableDurations(uint64 tokenId)
        external
        view
        returns (TimeElapsed memory sinceStaked, TimeElapsed memory sinceUnstaked)
    {
        sinceStaked = _getElapsed(lastStakedAt[tokenId]);
        sinceUnstaked = _getElapsed(lastUnstakedAt[tokenId]);
    }

    function _getElapsed(uint64 fromTimestamp) internal view returns (TimeElapsed memory) {
        if (fromTimestamp == 0 || fromTimestamp > block.timestamp) {
            return TimeElapsed(0, 0, 0, 0);
        }

        uint64 elapsed = uint64(block.timestamp) - fromTimestamp;
        uint64 daysElapsed = elapsed / 86400;
        elapsed %= 86400;
        uint64 hoursElapsed = elapsed / 3600;
        elapsed %= 3600;
        uint64 minutesElapsed = elapsed / 60;
        uint64 secondsElapsed = elapsed % 60;

        return TimeElapsed(daysElapsed, hoursElapsed, minutesElapsed, secondsElapsed);
    }
}