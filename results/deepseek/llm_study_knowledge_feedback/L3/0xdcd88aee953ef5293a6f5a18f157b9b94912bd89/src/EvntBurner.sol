// SPDX-License-Identifier: MIT

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract EvntBurner is Ownable, Pausable, ReentrancyGuard {
    string public constant NAME = "EvntBurner";
    string public constant VERSION = "5.0.0";

    address public constant DEAD_ADDRESS = address(0);

    uint64 public constant HALVING_INTERVAL = 100_000;
    uint64 public constant INITIAL_REWARD_BASE = 50_000_000_000_000_000_000;
    uint64 public constant BLUECHIP_BPS = 5000;
    uint64 public constant BPS_DENOMINATOR = 10_000;
    uint64 public constant MAX_BATCH = 50;
    uint64 public constant MAX_BLUECHIP_COLLECTIONS = 50;
    uint64 public constant MAX_WHITELIST_OPS_BATCH = 100;

    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;

    enum Status {
        None,
        Burn,
        Bluechip
    }

    uint64 public totalBurns;

    mapping(address => Status) public collectionStatus;

    address[] public bluechipCollections;

    event NFTBurned(address indexed user, address indexed collection, uint256 indexed tokenId);

    event Accrued(
        address indexed user,
        uint64 burnedCount,
        uint64 bluechipCount,
        uint64 totalEvnt,
        uint64 eraAtStart,
        uint64 eraAtEnd,
        uint64 totalBurnsAfter
    );

    event CollectionStatusSet(address indexed collection, Status indexed prevStatus, Status indexed newStatus);

    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);

    event TokensRescued(address indexed token, address indexed to, uint64 amount);

    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "EvntBurner: zero owner");
    }

    function burnBatch(address[] calldata collections, uint256[] calldata tokenIds)
        external
        whenNotPaused
        nonReentrant
    {
        uint64 len = uint64(collections.length);
        require(len != 0, "EmptyBatch");
        require(len == uint64(tokenIds.length), "ArrayLengthMismatch");
        require(len <= MAX_BATCH, "BatchTooLarge");

        address caller = tx.accounts.dataAccount.key;
        bool userIsBluechip = _userHoldsAnyBluechip(caller);

        uint64 burnsBefore = totalBurns;
        uint64 totalEvnt;

        address lastCol;
        Status lastStatus;

        for (uint64 i = 0; i < len; i++) {
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

            require(s != Status.None, "NotWhitelisted");
            require(s == Status.Burn, "NotBurnable");

            IERC721(col).transferFrom(caller, DEAD_ADDRESS, tokenId);

            emit NFTBurned(caller, col, tokenId);

            uint64 era = (burnsBefore + i) / HALVING_INTERVAL;
            uint64 baseReward = INITIAL_REWARD_BASE >> era;
            uint64 reward =
                userIsBluechip ? (baseReward * (BPS_DENOMINATOR + BLUECHIP_BPS)) / BPS_DENOMINATOR : baseReward;

            totalEvnt += reward;
        }

        uint64 burnsAfter = burnsBefore + len;
        totalBurns = burnsAfter;

        emit Accrued(
            caller,
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
        returns (uint64 totalEvnt, uint64[] memory perNftReward)
    {
        uint64 len = uint64(collections.length);
        require(len != 0, "EmptyBatch");
        require(len <= MAX_BATCH, "BatchTooLarge");

        perNftReward = new uint64[](len);
        uint64 burnsBefore = totalBurns;

        for (uint64 i = 0; i < len; i++) {
            address col = collections[i];
            Status s = collectionStatus[col];
            if (s == Status.Burn) {
                uint64 era = (burnsBefore + i) / HALVING_INTERVAL;
                uint64 baseReward = INITIAL_REWARD_BASE >> era;
                perNftReward[i] = baseReward;
                totalEvnt += baseReward;
            }
        }
    }

    function currentRewardBase() external view returns (uint64) {
        return INITIAL_REWARD_BASE >> (totalBurns / HALVING_INTERVAL);
    }

    function currentEra() external view returns (uint64) {
        return totalBurns / HALVING_INTERVAL;
    }

    function burnsUntilNextHalving() external view returns (uint64) {
        return HALVING_INTERVAL - (totalBurns % HALVING_INTERVAL);
    }

    function isBurnCollection(address col) external view returns (bool) {
        return collectionStatus[col] == Status.Burn;
    }

    function isBluechipCollection(address col) external view returns (bool) {
        return collectionStatus[col] == Status.Bluechip;
    }

    function bluechipCount() external view returns (uint64) {
        return uint64(bluechipCollections.length);
    }

    function getBluechipCollections() external view returns (address[] memory) {
        return bluechipCollections;
    }

    function _userHoldsAnyBluechip(address user) internal view returns (bool) {
        uint64 len = uint64(bluechipCollections.length);
        for (uint64 i = 0; i < len; i++) {
            address bc = bluechipCollections[i];
            (bool ok, bytes memory data) = bc.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", user));
            if (ok && data.length >= 32) {
                uint256 bal = abi.decode(data, (uint256));
                if (bal > 0) {
                    return true;
                }
            }
        }
        return false;
    }

    function addCollections(address[] calldata cols, Status target) external onlyOwner {
        uint64 len = uint64(cols.length);
        require(len != 0, "EmptyBatch");
        require(len <= MAX_WHITELIST_OPS_BATCH, "WhitelistBatchTooLarge");
        require(target != Status.None, "InvalidTargetStatus");

        for (uint64 i = 0; i < len; i++) {
            address col = cols[i];
            require(col != address(0), "ZeroAddress");
            require(col != DEAD_ADDRESS && col != address(this), "InvalidCollection");

            Status prev = collectionStatus[col];
            require(prev != target, "AlreadyInList");

            if (target == Status.Bluechip) {
                require(bluechipCollections.length < MAX_BLUECHIP_COLLECTIONS, "BluechipListFull");
                bluechipCollections.push(col);
            }
            if (prev == Status.Bluechip) {
                _removeBluechipFromArray(col);
            }

            collectionStatus[col] = target;
            emit CollectionStatusSet(col, prev, target);
        }
    }

    function removeCollections(address[] calldata cols) external onlyOwner {
        uint64 len = uint64(cols.length);
        require(len != 0, "EmptyBatch");
        require(len <= MAX_WHITELIST_OPS_BATCH, "WhitelistBatchTooLarge");

        for (uint64 i = 0; i < len; i++) {
            address col = cols[i];
            Status prev = collectionStatus[col];
            require(prev != Status.None, "NotInList");

            if (prev == Status.Bluechip) {
                _removeBluechipFromArray(col);
            }

            collectionStatus[col] = Status.None;
            emit CollectionStatusSet(col, prev, Status.None);
        }
    }

    function _removeBluechipFromArray(address col) internal {
        uint64 len = uint64(bluechipCollections.length);
        for (uint64 i = 0; i < len; i++) {
            if (bluechipCollections[i] == col) {
                if (i != len - 1) {
                    bluechipCollections[i] = bluechipCollections[len - 1];
                }
                bluechipCollections.pop();
                return;
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(tx.accounts.dataAccount.key);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(tx.accounts.dataAccount.key);
    }

    function rescueTokens(address token, address to, uint64 amount) external onlyOwner {
        require(token != address(0), "ZeroAddress");
        require(to != address(0), "ZeroAddress");
        (bool ok, bytes memory data) = token.call{accounts: []}(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "EvntBurner: rescue failed");
        emit TokensRescued(token, to, amount);
    }
}