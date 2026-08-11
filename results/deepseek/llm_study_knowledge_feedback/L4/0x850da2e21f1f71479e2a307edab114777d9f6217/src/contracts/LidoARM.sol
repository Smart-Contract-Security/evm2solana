// SPDX-License-Identifier: BUSL-1.1

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Solana SPL Token interface for token interactions
interface SPLToken {
    function approve(address spender, uint64 amount) external returns (bool);
    function transfer(address to, uint64 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint64);
}

// Lido Withdrawal Queue interface adapted for Solana
interface IStETHWithdrawal {
    struct WithdrawalRequestStatus {
        uint64 amountOfStETH;
        address owner;
        bool isClaimed;
    }

    function getWithdrawalRequests(address _owner) external view returns (uint64[] memory);
    function getWithdrawalStatus(uint64[] calldata _requestIds) external view returns (WithdrawalRequestStatus[] memory);
    function requestWithdrawals(uint64[] calldata _amounts, address _owner) external returns (uint64[] memory requestIds);
    function claimWithdrawals(uint64[] calldata _requestIds, uint64[] calldata _hints) external;
}

// WETH interface adapted for Solana (no value transfer)
interface IWETH {
    function deposit() external;
    function withdraw(uint64 amount) external;
}

/**
 * @title Lido (stETH) Automated Redemption Manager (ARM)
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * It also integrates to a CapManager contract that caps the amount of assets a liquidity provider
 * can deposit and caps the ARM's total assets.
 * A performance fee is also collected on increases in the ARM's total assets.
 * @author Origin Protocol Inc
 */
contract LidoARM is Initializable {
    /// @notice The address of the Lido stETH token
    address public immutable steth;
    /// @notice The address of the Wrapped ETH (WETH) token
    address public immutable weth;
    /// @notice The address of the Lido Withdrawal Queue contract
    address public immutable lidoWithdrawalQueue;

    /// @notice The amount of stETH in the Lido Withdrawal Queue
    uint64 public lidoWithdrawalQueueAmount;

    /// @notice stores the requested amount for each Lido withdrawal
    mapping(uint64 id => uint64 amount) public lidoWithdrawalRequests;

    // ARM base storage variables
    address public operator;
    string public name;
    string public symbol;
    uint64 public fee;
    address public feeCollector;
    address public capManager;
    uint64 public claimDelay;
    uint64 public minSharesToRedeem;
    int64 public allocateThreshold;
    address public asset;
    address public baseAsset;
    address public rewardAsset;
    address public owner;

    event RequestLidoWithdrawals(uint64[] amounts, uint64[] requestIds);
    event ClaimLidoWithdrawals(uint64[] requestIds);
    event RegisterLidoWithdrawalRequests(uint64[] requestIds, uint64 totalAmountRequested);

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "Caller is not the owner");
        _;
    }

    modifier onlyOperatorOrOwner() {
        require(
            tx.accounts.dataAccount.key == operator || tx.accounts.dataAccount.key == owner,
            "Caller is not operator or owner"
        );
        _;
    }

    /// @param _steth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the Lido's withdrawal queue contract
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    /// @param _minSharesToRedeem The minimum amount of shares to redeem from the active lending market
    /// @param _allocateThreshold The minimum amount of liquidity assets in excess of the ARM buffer before
    /// the ARM can allocate to a active lending market.
    constructor(
        address _steth,
        address _weth,
        address _lidoWithdrawalQueue,
        uint64 _claimDelay,
        uint64 _minSharesToRedeem,
        int64 _allocateThreshold
    ) {
        steth = _steth;
        weth = _weth;
        lidoWithdrawalQueue = _lidoWithdrawalQueue;
        asset = _weth;
        baseAsset = _steth;
        rewardAsset = _weth;
        claimDelay = _claimDelay;
        minSharesToRedeem = _minSharesToRedeem;
        allocateThreshold = _allocateThreshold;

        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 WETH.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 1,500 = 15% performance fee
    /// @param _feeCollector The account that can collect the performance fee
    /// @param _capManager The address of the CapManager contract
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint64 _fee,
        address _feeCollector,
        address _capManager
    ) external initializer {
        _initARM(_operator, _name, _symbol, _fee, _feeCollector, _capManager);

        // Approve the Lido withdrawal queue contract. Used for redemption requests.
        SPLToken(steth).approve(lidoWithdrawalQueue, type(uint64).max);
    }

    function _initARM(
        address _operator,
        string calldata _name,
        string calldata _symbol,
        uint64 _fee,
        address _feeCollector,
        address _capManager
    ) internal {
        operator = _operator;
        name = _name;
        symbol = _symbol;
        fee = _fee;
        feeCollector = _feeCollector;
        capManager = _capManager;
        owner = tx.accounts.dataAccount.key;
    }

    /**
     * @notice Register the Lido withdrawal requests to the ARM contract.
     * This can only be called once by the contract Owner.
     */
    function registerLidoWithdrawalRequests() external reinitializer(2) onlyOwner {
        uint64 totalAmountRequested = 0;
        // Get all the ARM's outstanding withdrawal requests
        uint64[] memory requestIds = IStETHWithdrawal(lidoWithdrawalQueue).getWithdrawalRequests(address(this));
        // Get the status of all the withdrawal requests. eg amount, owner, claimed status
        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses =
            IStETHWithdrawal(lidoWithdrawalQueue).getWithdrawalStatus(requestIds);

        for (uint64 i = 0; i < requestIds.length; i++) {
            // The following should always be true given the requestIds came from calling getWithdrawalRequests
            require(statuses[i].isClaimed == false, "Withdrawal already claimed");
            require(statuses[i].owner == address(this), "Withdrawal owner mismatch");

            // Store the amount of stETH of each Lido withdraw request
            lidoWithdrawalRequests[requestIds[i]] = statuses[i].amountOfStETH;
            totalAmountRequested += statuses[i].amountOfStETH;
        }

        require(totalAmountRequested == lidoWithdrawalQueueAmount, "Total amount mismatch");

        emit RegisterLidoWithdrawalRequests(requestIds, totalAmountRequested);
    }

    /**
     * @notice Request a stETH for ETH withdrawal.
     * Reference: https://docs.lido.fi/contracts/withdrawal-queue-erc721/
     * Note: There is a 1k amount limit. Caller should split large withdrawals in chunks of less or equal to 1k each.)
     */
    function requestLidoWithdrawals(uint64[] calldata amounts)
        external
        onlyOperatorOrOwner
        returns (uint64[] memory requestIds)
    {
        requestIds = IStETHWithdrawal(lidoWithdrawalQueue).requestWithdrawals(amounts, address(this));

        // Sum the total amount of stETH being withdraw
        uint64 totalAmountRequested = 0;
        for (uint64 i = 0; i < amounts.length; i++) {
            totalAmountRequested += amounts[i];

            // Store the amount of each withdrawal request
            lidoWithdrawalRequests[requestIds[i]] = amounts[i];
        }

        // Increase the Ether outstanding from the Lido Withdrawal Queue
        lidoWithdrawalQueueAmount += totalAmountRequested;

        emit RequestLidoWithdrawals(amounts, requestIds);
    }

    /**
     * @notice Claim the ETH owed from the redemption requests and convert it to WETH.
     * Before calling this method, caller should check on the request NFTs to ensure the withdrawal was processed.
     * Withdrawal NFTs that have been transferred in from another account will be reverted.
     * @param requestIds The request IDs of the withdrawal requests.
     * @param hintIds The hint IDs of the withdrawal requests.
     * Call `findCheckpointHints` on the Lido withdrawal queue contract to get the hint IDs.
     */
    function claimLidoWithdrawals(uint64[] calldata requestIds, uint64[] calldata hintIds) external {
        // Claim the NFTs for ETH.
        IStETHWithdrawal(lidoWithdrawalQueue).claimWithdrawals(requestIds, hintIds);

        // Reduce the amount outstanding from the Lido Withdrawal Queue.
        // The amount of ETH claimed from the Lido Withdrawal Queue can be less than the requested amount
        // in the event of a mass slashing event of Lido validators.
        uint64 totalAmountRequested = 0;
        for (uint64 i = 0; i < requestIds.length; i++) {
            // Read the requested amount from storage
            uint64 requestAmount = lidoWithdrawalRequests[requestIds[i]];

            // Validate the request came from this Lido ARM contract and not
            // transferred in from another account.
            require(requestAmount > 0, "Invalid withdrawal request");

            totalAmountRequested += requestAmount;
        }

        // Store the reduced outstanding withdrawals from the Lido Withdrawal Queue
        // Since withdrawal NFTs that have been transferred in from another account are reverted above,
        // this subtraction should never underflow.
        lidoWithdrawalQueueAmount -= totalAmountRequested;

        // Wrap all the received ETH to WETH. This can be less than the requested amount in the event of slashing.
        // On Solana, value transfer via function calls is unsupported. The WETH deposit with value is replaced
        // by a direct call to deposit, assuming the contract already holds the native balance.
        IWETH(weth).deposit();

        emit ClaimLidoWithdrawals(requestIds);
    }

    /**
     * @dev Calculates the amount of WETH expected to be returned from the Lido Withdrawal Queue.
     * The actual amount returned can be less in the event of a slashing.
     */
    function _externalWithdrawQueue() internal view returns (uint64) {
        return lidoWithdrawalQueueAmount;
    }

    // receive() function is not permitted on Solana target.
}