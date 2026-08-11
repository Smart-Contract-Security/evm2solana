// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract EvntBurner {
    // ─── Identity ────────────────────────────────────────────────────────
    string public constant NAME = "EvntBurner";
    string public constant VERSION = "5.0.0";

    // ─── Constants ───────────────────────────────────────────────────────
    // Solana does not support Ethereum address literals. Use bytes32 constant instead.
    bytes32 public constant DEAD_ADDRESS = bytes32(uint256(uint160(0x000000000000000000000000000000000000dEaD)));

    uint256 public constant HALVING_INTERVAL = 100_000;
    uint256 public constant INITIAL_REWARD_BASE = 50 ether;
    uint256 public constant BLUECHIP_BPS = 5000;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_BATCH = 50;
    uint256 public constant MAX_BLUECHIP_COLLECTIONS = 50;
    uint256 public constant MAX_WHITELIST_OPS_BATCH = 100;
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;

    // ─── Status enum ─────────────────────────────────────────────────────
    enum Status {
        None,
        Burn,
        Bluechip
    }

    // ─── Storage ─────────────────────────────────────────────────────────
    uint256 public totalBurns;
    mapping(address => Status) public collectionStatus;
    address[] public bluechipCollections;

    address private _owner;
    bool private _paused;
    bool private _reentrancyGuard;

    // ─── Events ──────────────────────────────────────────────────────────
    event NFTBurned(address indexed user, address indexed collection, uint256 indexed tokenId);
    event Accrued(
        address indexed user,
        uint256 burnedCount,
        uint256 bluechipCount,
        uint256 totalEvnt,
        uint256 eraAtStart,
        uint256 eraAtEnd,
        uint256 totalBurnsAfter
    );
    event CollectionStatusSet(address indexed collection, Status indexed prevStatus, Status indexed newStatus);
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        // msg.sender is not available on Solana. Use tx.origin or pass sender as argument.
        // For simplicity, we use tx.origin which is the signer of the transaction.
        if (msg.sender != _owner) revert("OwnableUnauthorizedAccount");
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert("EnforcedPause");
        _;
    }

    modifier whenPaused() {
        if (!_paused) revert("ExpectedPause");
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyGuard) revert("ReentrancyGuardReentrantCall");
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor(address initialOwner) {
        require(initialOwner != address(0), "EvntBurner: zero owner");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    // ─── Public / External: User write ───────────────────────────────────
    function burnBatch(address[] calldata collections, uint256[] calldata tokenIds)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 len = collections.length;
        if (len == 0) revert("EmptyBatch");
        if (len != tokenIds.length) revert("ArrayLengthMismatch");
        if (len > MAX_BATCH) revert("BatchTooLarge");

        // msg.sender not available, use tx.origin
        address sender = msg.sender;
        bool userIsBluechip = _userHoldsAnyBluechip(sender);

        uint256 burnsBefore = totalBurns;
        uint256 totalEvnt;

        address lastCol;
        Status lastStatus;

        for (uint256 i; i < len;) {
            address col = collections[i];
            uint256 tokenId = tokenIds[i];

            Status s;
            if (col == lastCol) {
                s = lastStatus;
            } else {
                s = collectionStatus[col];
                lastCol = col;
                lastStatus = s;
            }

            if (s == Status.None) revert("NotWhitelisted");
            if (s != Status.Burn) revert("NotBurnable");

            // transferFrom via external call
            // DEAD_ADDRESS is bytes32, need to convert to address for call.
            address deadAddr = address(uint160(uint256(DEAD_ADDRESS)));
            (bool success, ) = col.call{accounts: [sender, deadAddr]}(abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, deadAddr, tokenId));
            require(success, "transferFrom failed");

            emit NFTBurned(sender, col, tokenId);

            uint256 era = (burnsBefore + i) / HALVING_INTERVAL;
            uint256 baseReward = INITIAL_REWARD_BASE >> era;
            uint256 reward =
                userIsBluechip ? (baseReward * (BPS_DENOMINATOR + BLUECHIP_BPS)) / BPS_DENOMINATOR : baseReward;

            totalEvnt += reward;

            unchecked {
                ++i;
            }
        }

        uint256 burnsAfter = burnsBefore + len;
        totalBurns = burnsAfter;

        emit Accrued(
            sender,
            len,
            userIsBluechip ? 1 : 0,
            totalEvnt,
            burnsBefore / HALVING_INTERVAL,
            (burnsAfter - 1) / HALVING_INTERVAL,
            burnsAfter
        );
    }

    // ─── Public / External: Views ────────────────────────────────────────
    function previewBatchReward(address[] calldata collections)
        external
        view
        returns (uint256 totalEvnt, uint256[] memory perNftReward)
    {
        uint256 len = collections.length;
        if (len == 0) revert("EmptyBatch");
        if (len > MAX_BATCH) revert("BatchTooLarge");

        perNftReward = new uint256[](len);
        uint256 burnsBefore = totalBurns;

        for (uint256 i; i < len;) {
            address col = collections[i];
            Status s = collectionStatus[col];
            if (s == Status.Burn) {
                uint256 era = (burnsBefore + i) / HALVING_INTERVAL;
                uint256 baseReward = INITIAL_REWARD_BASE >> era;
                perNftReward[i] = baseReward;
                totalEvnt += baseReward;
            }
            unchecked {
                ++i;
            }
        }
    }

    function currentRewardBase() external view returns (uint256) {
        return INITIAL_REWARD_BASE >> (totalBurns / HALVING_INTERVAL);
    }

    function currentEra() external view returns (uint256) {
        return totalBurns / HALVING_INTERVAL;
    }

    function burnsUntilNextHalving() external view returns (uint256) {
        return HALVING_INTERVAL - (totalBurns % HALVING_INTERVAL);
    }

    function isBurnCollection(address col) external view returns (bool) {
        return collectionStatus[col] == Status.Burn;
    }

    function isBluechipCollection(address col) external view returns (bool) {
        return collectionStatus[col] == Status.Bluechip;
    }

    function bluechipCount() external view returns (uint256) {
        return bluechipCollections.length;
    }

    function getBluechipCollections() external view returns (address[] memory) {
        return bluechipCollections;
    }

    // ─── Internal helpers ────────────────────────────────────────────────
    function _userHoldsAnyBluechip(address user) internal view returns (bool) {
        uint256 len = bluechipCollections.length;
        for (uint256 i; i < len;) {
            address bc = bluechipCollections[i];
            // staticcall not supported on Solana. Use regular call with gas limit.
            // Solang supports call with gas, but staticcall is not available.
            // We'll use a regular call and check success.
            (bool success, bytes memory data) = bc.call(abi.encodeWithSignature("balanceOf(address)", user));
            if (success && data.length == 32) {
                uint256 bal = abi.decode(data, (uint256));
                if (bal > 0) {
                    return true;
                }
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    // ─── Public / External: Admin write ──────────────────────────────────
    function addCollections(address[] calldata cols, Status target) external onlyOwner {
        uint256 len = cols.length;
        if (len == 0) revert("EmptyBatch");
        if (len > MAX_WHITELIST_OPS_BATCH) revert("WhitelistBatchTooLarge");
        if (target == Status.None) revert("InvalidTargetStatus");

        for (uint256 i; i < len;) {
            address col = cols[i];
            if (col == address(0)) revert("ZeroAddress");
            address deadAddr = address(uint160(uint256(DEAD_ADDRESS)));
            if (col == deadAddr || col == address(this)) {
                revert("InvalidCollection");
            }

            Status prev = collectionStatus[col];
            if (prev == target) revert("AlreadyInList");

            if (target == Status.Bluechip) {
                if (bluechipCollections.length >= MAX_BLUECHIP_COLLECTIONS) {
                    revert("BluechipListFull");
                }
                bluechipCollections.push(col);
            }
            if (prev == Status.Bluechip) {
                _removeBluechipFromArray(col);
            }

            collectionStatus[col] = target;
            emit CollectionStatusSet(col, prev, target);

            unchecked {
                ++i;
            }
        }
    }

    function removeCollections(address[] calldata cols) external onlyOwner {
        uint256 len = cols.length;
        if (len == 0) revert("EmptyBatch");
        if (len > MAX_WHITELIST_OPS_BATCH) revert("WhitelistBatchTooLarge");

        for (uint256 i; i < len;) {
            address col = cols[i];
            Status prev = collectionStatus[col];
            if (prev == Status.None) revert("NotInList");

            if (prev == Status.Bluechip) {
                _removeBluechipFromArray(col);
            }

            collectionStatus[col] = Status.None;
            emit CollectionStatusSet(col, prev, Status.None);

            unchecked {
                ++i;
            }
        }
    }

    function _removeBluechipFromArray(address col) internal {
        uint256 len = bluechipCollections.length;
        for (uint256 i; i < len;) {
            if (bluechipCollections[i] == col) {
                if (i != len - 1) {
                    bluechipCollections[i] = bluechipCollections[len - 1];
                }
                bluechipCollections.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    function _pause() internal whenNotPaused {
        _paused = true;
    }

    function _unpause() internal whenPaused {
        _paused = false;
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) revert("ZeroAddress");
        if (to == address(0)) revert("ZeroAddress");
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "EvntBurner: rescue failed");
        emit TokensRescued(token, to, amount);
    }

    // ─── Ownership ───────────────────────────────────────────────────────
    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert("ZeroAddress");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function renounceOwnership() external onlyOwner {
        address oldOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(oldOwner, address(0));
    }

    // ─── Pausable views ──────────────────────────────────────────────────
    function paused() external view returns (bool) {
        return _paused;
    }
}