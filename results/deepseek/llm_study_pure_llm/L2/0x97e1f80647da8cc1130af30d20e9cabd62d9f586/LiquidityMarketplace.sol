// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin Contracts (last updated v4.9.0) (utils/StorageSlot.sol)

library StorageSlotUpgradeable {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly {
            r.slot := store.slot
        }
    }

    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := store.slot
        }
    }
}

interface IERC1967Upgradeable {
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
}

interface IBeaconUpgradeable {
    function implementation() external view returns (address);
}

interface IERC1822ProxiableUpgradeable {
    function proxiableUUID() external view returns (bytes32);
}

library AddressUpgradeable {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        if (returndata.length > 0) {
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

abstract contract Initializable {
    uint8 private _initialized;
    bool private _initializing;

    event Initialized(uint8 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

abstract contract ERC1967UpgradeUpgradeable is Initializable, IERC1967Upgradeable {
    function __ERC1967Upgrade_init() internal onlyInitializing {
    }

    function __ERC1967Upgrade_init_unchained() internal onlyInitializing {
    }

    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _getImplementation() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        require(AddressUpgradeable.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            AddressUpgradeable.functionDelegateCall(newImplementation, data);
        }
    }

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data, bool forceCall) internal {
        if (StorageSlotUpgradeable.getBooleanSlot(_ROLLBACK_SLOT).value) {
            _setImplementation(newImplementation);
        } else {
            try IERC1822ProxiableUpgradeable(newImplementation).proxiableUUID() returns (bytes32 slot) {
                require(slot == _IMPLEMENTATION_SLOT, "ERC1967Upgrade: unsupported proxiableUUID");
            } catch {
                revert("ERC1967Upgrade: new implementation is not UUPS");
            }
            _upgradeToAndCall(newImplementation, data, forceCall);
        }
    }

    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function _getAdmin() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value;
    }

    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function _getBeacon() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        require(AddressUpgradeable.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            AddressUpgradeable.isContract(IBeaconUpgradeable(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    function _upgradeBeaconToAndCall(address newBeacon, bytes memory data, bool forceCall) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            AddressUpgradeable.functionDelegateCall(IBeaconUpgradeable(newBeacon).implementation(), data);
        }
    }

    uint256[50] private __gap;
}

abstract contract UUPSUpgradeable is Initializable, IERC1822ProxiableUpgradeable, ERC1967UpgradeUpgradeable {
    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }

    address private immutable __self = address(this);

    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    modifier notDelegated() {
        require(address(this) == __self, "UUPSUpgradeable: must not be called through delegatecall");
        _;
    }

    function proxiableUUID() external view virtual override notDelegated returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    function upgradeTo(address newImplementation) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, new bytes(0), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    uint256[50] private __gap;
}

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }

    uint256[49] private __gap;
}

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    uint256[50] private __gap;
}

abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    uint256[49] private __gap;
}

interface ILiquidityLocker {
    function transferLockOwnership(
        address _lpToken,
        uint256 _index,
        uint256 _lockID,
        address payable _newOwner
    ) external;

    function getUserLockForTokenAtIndex(
        address _user,
        address _lpToken,
        uint256 _index
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, address);
}

contract LiquidityMarketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    ILiquidityLocker public liquidityLocker;

    struct Deal {
        address borrower;
        address lpToken;
        uint256 lockIndex;
        uint256 dealAmount;
        uint256 interestRate;
        uint256 loanDuration;
        uint256 startTime;
        address lender;
        bool isRepaid;
        bool isActive;
        bool collateralClaimed;
    }

    struct Auction {
        address owner;
        address highestBidOwner;
        address lpToken;
        uint256 lockIndex;
        uint256 startPrice;
        uint256 imeddiatelySellPrice;
        uint256 bidStep;
        uint256 duration;
        uint256 startTime;
        bool isActive;
        bool isFinishedImmediately;
        bool immediatelySell;
        bool isRewardClaimed;
    }

    mapping(address => uint256[]) private userDeals;
    mapping(address => uint256[]) private userAuction;
    mapping(address => mapping(uint256  => bool)) public activeDealLiquidityLockId;
    mapping(uint256 => bool) public auctionClaimed;

    mapping(uint256 => mapping(address => uint256)) bids;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Deal) public deals;
    uint256 public nextAuctionId;
    uint256 public nextDealId;
    uint256 public ownerFee;
    address public feeReceiver;

    event DealInitialized(
        uint256 indexed dealId,
        address indexed borrower,
        address lpToken,
        uint256 lockIndex,
        uint256 dealAmount,
        uint256 interestRate,
        uint256 loanDuration
    );
    event DealActivated(uint256 indexed dealId, address indexed activator);
    event DealMade(uint256 indexed dealId, address indexed lender);
    event LoanRepaid(uint256 indexed dealId, address indexed repayer);
    event CollateralClaimed(uint256 indexed dealId, address indexed claimer);
    event AuctionStarted(
        uint256 indexed auctionId,
        address indexed owner,
        address lpToken,
        uint256 lockIndex,
        uint256 startPrice,
        uint256 imeddiatelySellPrice,
        uint256 bidStep,
        uint256 duration,
        bool immediatelySell
    );
    event AuctionActivated(
        uint256 indexed auctionId,
        address indexed activator
    );
    event BidMade(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );
    event AuctionWon(uint256 indexed auctionId, address indexed winner);
    event AuctionRewardClaimed(
        uint256 indexed auctionId,
        address indexed owner,
        uint256 amount,
        uint256 timestamp
    );
    event BidWithdrawn(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );
    event ImmediatelyBought(
        uint256 indexed auctionId,
        uint256 amount,
        uint256 timestamp
    );

    function initialize(
        ILiquidityLocker _liquidityLocker,
        uint256 _ownerFee,
        address _feeReceiver
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        require(_ownerFee < 10000, "Owner fee must be less than 10000");
        require(
            _feeReceiver != address(0),
            "Fee receiver cannot be zero address"
        );
        liquidityLocker = _liquidityLocker;
        ownerFee = _ownerFee;
        feeReceiver = _feeReceiver;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function setOwnerFee(uint256 _ownerFee) external onlyOwner {
        require(_ownerFee < 10000, "Owner fee must be less than 10000");
        ownerFee = _ownerFee;
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        require(
            _feeReceiver != address(0),
            "Fee receiver cannot be zero address"
        );
        feeReceiver = _feeReceiver;
    }

    function checkLiquidityOwner(
        address expectedOwner,
        address lpToken,
        uint256 index
    ) public view returns (bool) {
        (, , , , , address owner) = liquidityLocker.getUserLockForTokenAtIndex(
            expectedOwner,
            lpToken,
            index
        );
        return owner == expectedOwner;
    }

    function getUserDeals(
        address _address
    ) external view returns (uint256[] memory) {
        return userDeals[_address];
    }

    function getUserAuction(
        address _address
    ) external view returns (uint256[] memory) {
        return userAuction[_address];
    }

    function initializeDeal(
        address lpToken,
        uint256 lockIndex,
        uint256 dealAmount,
        uint256 interestRate,
        uint256 loanDuration
    ) public UniqueLock(msg.sender, lpToken, lockIndex) {
        require(loanDuration > 0, "Loan duration must be greater than 0");
        require(
            checkLiquidityOwner(msg.sender, lpToken, lockIndex),
            "User does not owner of this lock"
        );
        require(interestRate > 0, "interestRate must be greater than 0");
        require(dealAmount > 0, "dealAmount must be greater than 0");

        deals[nextDealId] = Deal({
            borrower: msg.sender,
            lpToken: lpToken,
            lockIndex: lockIndex,
            dealAmount: dealAmount,
            interestRate: interestRate,
            loanDuration: loanDuration,
            startTime: 0,
            lender: address(0),
            isRepaid: false,
            isActive: false,
            collateralClaimed: false
        });

        emit DealInitialized(
            nextDealId,
            msg.sender,
            lpToken,
            lockIndex,
            dealAmount,
            interestRate,
            loanDuration
        );

        userDeals[msg.sender].push(nextDealId);

        nextDealId++;
    }

    function activateDeal(uint256 dealId) external {
        Deal storage deal = deals[dealId];
        require(deal.borrower != address(0), "Deal is empty");
        require(
            checkLiquidityOwner(address(this), deal.lpToken, deal.lockIndex),
            "Contract does not owner of this liquidity"
        );
        deal.isActive = true;
        emit DealActivated(dealId, msg.sender);
    }

    function makeDeal(uint256 dealId) external payable nonReentrant {
        Deal storage deal = deals[dealId];
        require(msg.sender.code.length == 0, "Caller cannot be a smart contract");
        require(deal.isActive, "Deal inactive");
        require(deal.lender == address(0), "Deal already has a lender");
        require(
            deal.borrower != msg.sender,
            "Borrower cannot make loan for himself"
        );
        require(msg.value >= deal.dealAmount, "Insufficient funds");

        deal.lender = msg.sender;
        deal.startTime = block.timestamp;

        uint256 feeAmount = (deal.dealAmount * ownerFee) / 10000;
        (bool feeSent, ) = payable(feeReceiver).call{value: feeAmount}("");
        require(feeSent, "Failed to send fee");

        (bool sent, ) = payable(deal.borrower).call{
            value: msg.value - feeAmount
        }("");
        require(sent, "Failed to send funds");

        emit DealMade(dealId, msg.sender);
    }

    function cancelDeal(uint256 dealId) public {
        Deal storage deal = deals[dealId];
        require(deal.borrower == msg.sender, "Caller not lock owner");
        require(deal.lender == address(0), "Cannot cancel processing deal");
        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            address(this),
            deal.lpToken,
            deal.lockIndex
        );
        activeDealLiquidityLockId[deal.lpToken][lockId] = false;
        liquidityLocker.transferLockOwnership(
            deal.lpToken,
            deal.lockIndex,
            lockId,
            payable(msg.sender)
        );
        delete deals[dealId];
    }

    function repayLoan(uint256 dealId) public payable nonReentrant {
        Deal storage deal = deals[dealId];
        uint256 repayAmount = deal.dealAmount +
            (deal.dealAmount * deal.interestRate) /
            10000;
        require(!deal.isRepaid, "Deal already repaid");
        require(msg.sender == deal.borrower, "Sender is not a borrower");
        require(deal.lender != address(0), "Nothing to repay");
        require(msg.value >= repayAmount, "Insuffitient payable amount");
        require(
            deal.startTime + deal.loanDuration > block.timestamp,
            "Loan duration exceed"
        );
        deal.isRepaid = true;
        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            address(this),
            deal.lpToken,
            deal.lockIndex
        );
        activeDealLiquidityLockId[deal.lpToken][lockId] = false;
        liquidityLocker.transferLockOwnership(
            deal.lpToken,
            deal.lockIndex,
            lockId,
            payable(msg.sender)
        );
        (bool sent, ) = payable(deal.lender).call{value: msg.value}("");
        require(sent, "Repay failed");
        emit LoanRepaid(dealId, msg.sender);
    }

    function claimCollateral(uint256 dealId) public nonReentrant {
        Deal storage deal = deals[dealId];
        require(deal.lender == msg.sender, "Caller is not lender");
        require(!deal.collateralClaimed, "Already claimed");
        require(
            deal.startTime + deal.loanDuration < block.timestamp,
            "Deal is active yet"
        );
        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            address(this),
            deal.lpToken,
            deal.lockIndex
        );
        activeDealLiquidityLockId[deal.lpToken][lockId] = false;
        liquidityLocker.transferLockOwnership(
            deal.lpToken,
            deal.lockIndex,
            lockId,
            payable(msg.sender)
        );
        deal.collateralClaimed = true;
        emit CollateralClaimed(dealId, msg.sender);
    }

    function startAuction(
        address lpToken,
        uint256 lockIndex,
        uint256 startPrice,
        uint256 imeddiatelySellPrice,
        uint256 bidStep,
        uint256 duration,
        bool immediatelySell
    ) public UniqueLock(msg.sender, lpToken, lockIndex) {
        require(duration > 0, "Duration must be greater than 0");
        require(
            checkLiquidityOwner(msg.sender, lpToken, lockIndex),
            "User does not owner of this lock"
        );
        require(
            imeddiatelySellPrice > 0,
            "imeddiatelySellPrice must be positive number"
        );

        auctions[nextAuctionId] = Auction({
            owner: msg.sender,
            highestBidOwner: address(0),
            lpToken: lpToken,
            lockIndex: lockIndex,
            startPrice: startPrice,
            imeddiatelySellPrice: imeddiatelySellPrice,
            bidStep: bidStep,
            duration: duration,
            startTime: block.timestamp,
            isActive: false,
            isFinishedImmediately: false,
            immediatelySell: immediatelySell,
            isRewardClaimed: false
        });
        emit AuctionStarted(
            nextAuctionId,
            msg.sender,
            lpToken,
            lockIndex,
            startPrice,
            imeddiatelySellPrice,
            bidStep,
            duration,
            immediatelySell
        );

        userAuction[msg.sender].push(nextAuctionId);

        nextAuctionId++;
    }

    function activateAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(!auction.isActive, "Auction already active");
        require(auction.owner != address(0), "Auction is empty");
        require(
            checkLiquidityOwner(
                address(this),
                auction.lpToken,
                auction.lockIndex
            ),
            "Contract does not owner of this liquidity"
        );
        auction.isActive = true;
        auction.startTime = block.timestamp;
        emit AuctionActivated(auctionId, msg.sender);
    }

    function immediatelyBuy(uint256 auctionId) external payable nonReentrant{
        Auction storage auction = auctions[auctionId];
        require(msg.sender.code.length == 0, "Caller cannot be a smart contract");
        require(
            auction.immediatelySell,
            "Immediately selling is disabled for this lottery"
        );
        require(auction.owner != msg.sender, "Sender is auction owner");
        require(
            msg.value >= auction.imeddiatelySellPrice,
            "Insuffitient payable amount"
        );
        require(
            !auction.isFinishedImmediately &&
                auction.isActive &&
                auction.startTime + auction.duration > block.timestamp,
            "Auction inactive"
        );
        auction.isFinishedImmediately = true;
        auction.highestBidOwner = address(0);
        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            address(this),
            auction.lpToken,
            auction.lockIndex
        );
        activeDealLiquidityLockId[auction.lpToken][lockId] = false;
        liquidityLocker.transferLockOwnership(
            auction.lpToken,
            auction.lockIndex,
            lockId,
            payable(msg.sender)
        );

        uint256 feeAmount = (msg.value * ownerFee) / 10000;
        (bool feeSent, ) = payable(feeReceiver).call{value: feeAmount}("");
        require(feeSent, "Failed to send fee");

        (bool sent, ) = payable(auction.owner).call{
            value: msg.value - feeAmount
        }("");
        require(sent, "Failed to send funds");
        emit ImmediatelyBought(auctionId, msg.value, block.timestamp);
    }

    function makeBid(uint256 auctionId) public payable {
        Auction storage auction = auctions[auctionId];
        require(
            !auction.isFinishedImmediately &&
                auction.isActive &&
                auction.startTime + auction.duration > block.timestamp,
            "Auction inactive"
        );
        require(auction.owner != msg.sender, "Sender is auction owner");
        require(bids[auctionId][msg.sender] + msg.value >= auction.startPrice, "Bid amount must be greater than startPrice");
        require(
            bids[auctionId][msg.sender] + msg.value >=
                bids[auctionId][auction.highestBidOwner] + auction.bidStep,
            "Bid must be greater than previous + bidStep"
        );
        bids[auctionId][msg.sender] += msg.value;
        auction.highestBidOwner = msg.sender;
        emit BidMade(auctionId, msg.sender, msg.value, block.timestamp);
    }

    function withdrawAuctionLiquidity(uint256 auctionId) public {
        Auction storage auction = auctions[auctionId];
        require(
            auction.startTime + auction.duration < block.timestamp,
            "Auction is active yet"
        );
        require(
            auction.highestBidOwner == address(0) &&
                !auction.isFinishedImmediately,
            "Not claimable"
        );
        require(msg.sender == auction.owner, "Caller is not auction owner");

        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            address(this),
            auction.lpToken,
            auction.lockIndex
        );
        activeDealLiquidityLockId[auction.lpToken][lockId] = false;
        liquidityLocker.transferLockOwnership(
            auction.lpToken,
            auction.lockIndex,
            lockId,
            payable(msg.sender)
        );
    }

    function claimAuction(uint256 auctionId) public nonReentrant{
        Auction memory auction = auctions[auctionId];
        require(
                auction.startTime + auction.duration < block.timestamp,
            "Auction is active yet"
        );
        require(
            msg.sender == auction.highestBidOwner &&
                !auction.isFinishedImmediately,
            "Not eligible for claim"
        );
        require(!auctionClaimed[auctionId], "Already claimed");
        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            address(this),
            auction.lpToken,
            auction.lockIndex
        );
        activeDealLiquidityLockId[auction.lpToken][lockId] = false;
        liquidityLocker.transferLockOwnership(
            auction.lpToken,
            auction.lockIndex,
            lockId,
            payable(msg.sender)
        );
        auctionClaimed[auctionId] = true;
        emit AuctionWon(auctionId, msg.sender);
    }

    function claimAuctionReward(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(
            !auction.isFinishedImmediately &&
                auction.startTime + auction.duration < block.timestamp,
            "Auction active yet"
        );
        require(msg.sender == auction.owner && !auction.isRewardClaimed, "Not eligible for claim");
        uint256 bidAmount = bids[auctionId][auction.highestBidOwner];

        require(bidAmount > 0, "Nothing to claim");

        uint256 feeAmount = (bidAmount * ownerFee) / 10000;

        (bool feeSent, ) = payable(feeReceiver).call{value: feeAmount}("");
        require(feeSent, "Failed to send fee");

        (bool sent, ) = payable(msg.sender).call{value: bidAmount - feeAmount}(
            ""
        );
        require(sent, "Withdraw failed");
        auction.isRewardClaimed = true;
        emit AuctionRewardClaimed(
            auctionId,
            msg.sender,
            bidAmount,
            block.timestamp
        );
    }

    function withdrawBid(uint256 auctionId) external nonReentrant{
        Auction storage auction = auctions[auctionId];
        uint256 bidAmount = bids[auctionId][msg.sender];
        require(
            msg.sender != auction.highestBidOwner && bidAmount > 0,
            "No eligible to withdraw"
        );
        (bool sent, ) = payable(msg.sender).call{value: bidAmount}("");
        require(sent, "Withdraw failed");
        bids[auctionId][msg.sender] = 0;
        emit BidWithdrawn(auctionId, msg.sender, bidAmount, block.timestamp);
    }

    modifier UniqueLock(address user, address lpToken, uint256 index) {
        (, , , , uint256 lockId, ) = liquidityLocker.getUserLockForTokenAtIndex(
            user,
            lpToken,
            index
        );
        require(!activeDealLiquidityLockId[lpToken][lockId], "Can only initialize deals with unique locks");
        activeDealLiquidityLockId[lpToken][lockId] = true;
        _;
    }
}