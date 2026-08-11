// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IStETHWithdrawal {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory);
    function getWithdrawalStatus(uint256[] calldata _requestIds) external view returns (WithdrawalRequestStatus[] memory);
    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
}

abstract contract AbstractARM {
    address public immutable baseToken;
    address public immutable yieldToken;
    address public immutable rewardToken;
    uint256 public claimDelay;
    uint256 public minSharesToRedeem;
    int256 public allocateThreshold;

    address public operator;
    address public owner;
    address public feeCollector;
    address public capManager;
    uint256 public fee;
    string public name;
    string public symbol;

    bool private _initialized;
    bool private _initializing;

    modifier onlyOwner() {
        require(tx.accounts[0].key == owner, "Not owner");
        _;
    }

    modifier onlyOperatorOrOwner() {
        require(tx.accounts[0].key == operator || tx.accounts[0].key == owner, "Not operator or owner");
        _;
    }

    modifier initializer() {
        require(!_initialized && !_initializing, "Already initialized");
        _initializing = true;
        _;
        _initialized = true;
        _initializing = false;
    }

    modifier reinitializer(uint8 version) {
        require(_initializing, "Not initializing");
        _;
    }

    constructor(
        address _baseToken,
        address _yieldToken,
        address _rewardToken,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem,
        int256 _allocateThreshold
    ) {
        baseToken = _baseToken;
        yieldToken = _yieldToken;
        rewardToken = _rewardToken;
        claimDelay = _claimDelay;
        minSharesToRedeem = _minSharesToRedeem;
        allocateThreshold = _allocateThreshold;
        owner = tx.accounts[0].key;
    }

    function _initARM(
        address _operator,
        string memory _name,
        string memory _symbol,
        uint256 _fee,
        address _feeCollector,
        address _capManager
    ) internal {
        operator = _operator;
        name = _name;
        symbol = _symbol;
        fee = _fee;
        feeCollector = _feeCollector;
        capManager = _capManager;
    }

    function _externalWithdrawQueue() internal view virtual returns (uint256);
}

contract LidoARM is AbstractARM {
    IERC20 public immutable steth;
    IWETH public immutable weth;
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    uint256 public lidoWithdrawalQueueAmount;

    mapping(uint256 => uint256) public lidoWithdrawalRequests;

    event RequestLidoWithdrawals(uint256[] amounts, uint256[] requestIds);
    event ClaimLidoWithdrawals(uint256[] requestIds);
    event RegisterLidoWithdrawalRequests(uint256[] requestIds, uint256 totalAmountRequested);

    constructor(
        address _steth,
        address _weth,
        address _lidoWithdrawalQueue,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem,
        int256 _allocateThreshold
    ) AbstractARM(_weth, _steth, _weth, _claimDelay, _minSharesToRedeem, _allocateThreshold) {
        steth = IERC20(_steth);
        weth = IWETH(_weth);
        lidoWithdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);
    }

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint256 _fee,
        address _feeCollector,
        address _capManager
    ) external initializer {
        _initARM(_operator, _name, _symbol, _fee, _feeCollector, _capManager);

        steth.approve(address(lidoWithdrawalQueue), type(uint256).max);
    }

    function registerLidoWithdrawalRequests() external reinitializer(2) onlyOwner {
        uint256 totalAmountRequested = 0;
        uint256[] memory requestIds = lidoWithdrawalQueue.getWithdrawalRequests(address(this));
        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses =
            lidoWithdrawalQueue.getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < requestIds.length; i++) {
            require(statuses[i].isClaimed == false, "LidoARM: already claimed");
            require(statuses[i].owner == address(this), "LidoARM: not owner");

            lidoWithdrawalRequests[requestIds[i]] = statuses[i].amountOfStETH;
            totalAmountRequested += statuses[i].amountOfStETH;
        }

        require(totalAmountRequested == lidoWithdrawalQueueAmount, "LidoARM: missing requests");

        emit RegisterLidoWithdrawalRequests(requestIds, totalAmountRequested);
    }

    function requestLidoWithdrawals(uint256[] calldata amounts)
        external
        onlyOperatorOrOwner
        returns (uint256[] memory requestIds)
    {
        requestIds = lidoWithdrawalQueue.requestWithdrawals(amounts, address(this));

        uint256 totalAmountRequested = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmountRequested += amounts[i];

            lidoWithdrawalRequests[requestIds[i]] = amounts[i];
        }

        lidoWithdrawalQueueAmount += totalAmountRequested;

        emit RequestLidoWithdrawals(amounts, requestIds);
    }

    function claimLidoWithdrawals(uint256[] calldata requestIds, uint256[] calldata hintIds) external {
        lidoWithdrawalQueue.claimWithdrawals(requestIds, hintIds);

        uint256 totalAmountRequested = 0;
        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 requestAmount = lidoWithdrawalRequests[requestIds[i]];

            require(requestAmount > 0, "LidoARM: invalid request");

            totalAmountRequested += requestAmount;
        }

        lidoWithdrawalQueueAmount -= totalAmountRequested;

        weth.deposit{value: address(this).balance}();

        emit ClaimLidoWithdrawals(requestIds);
    }

    function _externalWithdrawQueue() internal view override returns (uint256) {
        return lidoWithdrawalQueueAmount;
    }

    fallback() external payable {}
}