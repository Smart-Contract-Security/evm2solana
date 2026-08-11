// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function balanceOf(address owner) external view returns (uint256);
}

contract EvntBurner is Ownable, Pausable, ReentrancyGuard {
    string public constant NAME = "EvntBurner";
    string public constant VERSION = "5.0.0";

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant HALVING_INTERVAL = 100_000;
    uint256 public constant INITIAL_REWARD_BASE = 50 ether;
    uint256 public constant BLUECHIP_BPS = 5000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public constant MAX_BATCH = 50;
    uint256 public constant MAX_BLUECHIP_COLLECTIONS = 50;
    uint256 public constant MAX_WHITELIST_OPS_BATCH = 100;

    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;

    enum Status {
        None,
        Burn,
        Bluechip
    }

    uint256 public totalBurns;

    mapping(address => Status) public collectionStatus;

    address[] public bluechipCollections;

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

    error ZeroAddress();
    error InvalidCollection(address collection);

    error EmptyBatch();
    error BatchTooLarge(uint256 provided, uint256 max);
    error ArrayLengthMismatch();
    error NotWhitelisted(address collection);
    error NotBurnable(address collection);
    error NotTokenOwner(address collection, uint256 tokenId);
    error DuplicateInBatch(address collection, uint256 tokenId);

    error AlreadyInList(address collection, Status status);
    error NotInList(address collection);
    error InvalidTargetStatus(Status target);
    error WhitelistBatchTooLarge(uint256 size, uint256 maxSize);
    error BluechipListFull(uint256 max);

    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "EvntBurner: zero owner");
    }

    function burnBatch(address[] calldata collections, uint256[] calldata tokenIds)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 len = collections.length;
        if (len == 0) revert EmptyBatch();
        if (len != tokenIds.length) revert ArrayLengthMismatch();
        if (len > MAX_BATCH) revert BatchTooLarge(len, MAX_BATCH);

        bool userIsBluechip = _userHoldsAnyBluechip(msg.sender);

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

            if (s == Status.None) revert NotWhitelisted(col);
            if (s != Status.Burn) revert NotBurnable(col);

            bytes32 key = keccak256(abi.encodePacked(col, tokenId));
            uint256 seen;
            assembly ("memory-safe") {
                seen := tload(key)
            }
            if (seen != 0) revert DuplicateInBatch(col, tokenId);
            assembly ("memory-safe") {
                tstore(key, 1)
            }

            IERC721(col).transferFrom(msg.sender, DEAD_ADDRESS, tokenId);

            emit NFTBurned(msg.sender, col, tokenId);

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
            msg.sender,
            len,
            userIsBluechip ? 1 : 0,
            totalEvnt,
            burnsBefore / HALVING_INTERVAL,
            (burnsAfter - 1) / HALVING_INTERVAL,
            burnsAfter
        );
    }

    function previewBatchReward(address[] calldata collections)
        external
        view
        returns (uint256 totalEvnt, uint256[] memory perNftReward)
    {
        uint256 len = collections.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_BATCH) revert BatchTooLarge(len, MAX_BATCH);

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

    function _userHoldsAnyBluechip(address user) internal view returns (bool) {
        uint256 len = bluechipCollections.length;
        for (uint256 i; i < len;) {
            address bc = bluechipCollections[i];
            try IERC721(bc).balanceOf{gas: 30_000}(user) returns (uint256 bal) {
                if (bal > 0) {
                    return true;
                }
            } catch {
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function addCollections(address[] calldata cols, Status target) external onlyOwner {
        uint256 len = cols.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_WHITELIST_OPS_BATCH) revert WhitelistBatchTooLarge(len, MAX_WHITELIST_OPS_BATCH);
        if (target == Status.None) revert InvalidTargetStatus(target);

        for (uint256 i; i < len;) {
            address col = cols[i];
            if (col == address(0)) revert ZeroAddress();
            if (col == DEAD_ADDRESS || col == address(this)) {
                revert InvalidCollection(col);
            }

            Status prev = collectionStatus[col];
            if (prev == target) revert AlreadyInList(col, prev);

            if (target == Status.Bluechip) {
                if (bluechipCollections.length >= MAX_BLUECHIP_COLLECTIONS) {
                    revert BluechipListFull(MAX_BLUECHIP_COLLECTIONS);
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
        if (len == 0) revert EmptyBatch();
        if (len > MAX_WHITELIST_OPS_BATCH) revert WhitelistBatchTooLarge(len, MAX_WHITELIST_OPS_BATCH);

        for (uint256 i; i < len;) {
            address col = cols[i];
            Status prev = collectionStatus[col];
            if (prev == Status.None) revert NotInList(col);

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

    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "EvntBurner: rescue failed");
        emit TokensRescued(token, to, amount);
    }
}