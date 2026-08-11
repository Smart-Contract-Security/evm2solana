// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {IERC20} from "./openzeppelin/5.6/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "./openzeppelin/5.6/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "./openzeppelin/5.6/contracts/utils/ReentrancyGuardTransient.sol";

import {TriggerableWithdrawals} from "./base/TriggerableWithdrawals.sol";
import {IEAGStakingRouter} from "./interfaces/IEAGStakingRouter.sol";
import {IEAGVaultFactory} from "./interfaces/IEAGVaultFactory.sol";
import {IEAGVaultOperator} from "./interfaces/IEAGVaultOperator.sol";
import {IEAGWithdrawVault} from "./interfaces/IEAGWithdrawVault.sol";
import {ErrorsLib} from "./base/ErrorsLib.sol";
import {ConstantLib} from "./base/ConstantLib.sol";

/// @title EAGWithdrawVault - Per-user staking vault for validator withdrawals
/// @notice Receives validator withdrawals and EL rewards. Fee management (rates,
///         receivers, claiming) is delegated to EAGVaultOperator; this vault only
///         holds and distributes ETH when instructed by the operator.
///         Non-upgradeable; deployed by StakingRouter via EAGVaultFactory (CREATE2).
contract EAGWithdrawVault is IEAGWithdrawVault, ReentrancyGuardTransient {
    // ═══════════════════════════════════════════
    //               IMMUTABLES
    // ═══════════════════════════════════════════

    /// @notice The EAGVaultFactory that deployed this vault
    IEAGVaultFactory public immutable VAULT_FACTORY;

    // ═══════════════════════════════════════════
    //            STATE VARIABLES
    // ═══════════════════════════════════════════

    bool private _initialized;
    address private _EAGVaultOperator;
    address private _owner;
    address private _pendingOwner;
    uint256 private _pendingOwnerBalance;

    // ═══════════════════════════════════════════
    //                MODIFIERS
    // ═══════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == _owner, ErrorsLib.SenderNotOwner());
        _;
    }

    modifier onlyEAGVaultFactory() {
        require(
            msg.sender == address(VAULT_FACTORY),
            ErrorsLib.SenderNotEAGVaultFactory()
        );
        _;
    }

    modifier onlyEAGVaultOperator() {
        require(msg.sender == _EAGVaultOperator, ErrorsLib.SenderNotEAGVaultOperator());
        _;
    }

    // ═══════════════════════════════════════════
    //               CONSTRUCTOR
    // ═══════════════════════════════════════════

    /// @notice Deploy the vault implementation with a reference to the factory
    /// @param _factory The EAGVaultFactory contract address
    constructor(address _factory) {
        require(_factory != address(0), ErrorsLib.ZeroArgument("_EAGVaultFactory"));
        VAULT_FACTORY = IEAGVaultFactory(_factory);
    }

    /// @notice Accept incoming ETH (validator withdrawals and EL rewards)
    receive() external payable {}

    // ═══════════════════════════════════════════
    //             INITIALIZATION
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGWithdrawVault
    function initialize(
        address _initOwner,
        address _vaultOperator
    ) external onlyEAGVaultFactory {
        require(!_initialized, ErrorsLib.AlreadyInitialized());
        require(_initOwner != address(0), ErrorsLib.ZeroArgument("_initOwner"));
        require(_vaultOperator != address(0), ErrorsLib.ZeroArgument("_vaultOperator"));
        _initialized = true;
        _EAGVaultOperator = _vaultOperator;
        _owner = _initOwner;
        emit VaultInitialized(_initOwner, _vaultOperator);
    }

    // ═══════════════════════════════════════════
    //             VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGWithdrawVault
    function EAGVaultOperator() external view returns (address) {
        return _EAGVaultOperator;
    }

    /// @inheritdoc IEAGWithdrawVault
    function owner() external view returns (address) {
        return _owner;
    }

    /// @inheritdoc IEAGWithdrawVault
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /// @inheritdoc IEAGWithdrawVault
    function withdrawalCredentials() public view returns (bytes32) {
        return bytes32(ConstantLib.WC_0X02_PREFIX | uint160(address(this)));
    }

    /// @inheritdoc IEAGWithdrawVault
    function availableBalance() public view returns (uint256) {
        require(_EAGVaultOperator != address(0), ErrorsLib.EAGVaultOperatorNotInitialized());
        IEAGVaultOperator.VaultData memory data = IEAGVaultOperator(
            _EAGVaultOperator
        ).getVaultData(address(this));
        uint256 totalAmountInVault = data.accruedRewards + data.accruedWithdrawnPrincipalAmount;
        uint256 totalFees = data.accruedServiceFeeAmount + data.accruedContributionFeeAmount;
        uint256 operatorAvailable = totalAmountInVault > totalFees ? totalAmountInVault - totalFees : 0;
        return operatorAvailable + _pendingOwnerBalance;
    }

    /// @inheritdoc IEAGWithdrawVault
    function balanceOf() public view returns (uint256) {
        return address(this).balance;
    }

    /// @inheritdoc IEAGWithdrawVault
    function pendingOwnerBalance() external view returns (uint256) {
        return _pendingOwnerBalance;
    }

    /// @inheritdoc IEAGWithdrawVault
    function reconcileState() external view returns (uint256 balance, uint256 pendingBalance) {
        return (address(this).balance, _pendingOwnerBalance);
    }

    // ══════════════════════════════════════════════════
    //     VAULT OPERATOR: VALIDATOR WITHDRAWAL
    // ══════════════════════════════════════════════════

    /// @inheritdoc IEAGWithdrawVault
    function triggerValidatorWithdrawal(
        bytes calldata _pubkey,
        uint64 _amountInGwei,
        address _excessRefundRecipient
    ) external payable onlyEAGVaultOperator nonReentrant {
        require(msg.value > 0, ErrorsLib.ZeroArgument("msg.value"));
        require(_pubkey.length == ConstantLib.PUBLIC_KEY_LENGTH, ErrorsLib.InvalidPubkeyLength());
        require(
            _excessRefundRecipient != address(0),
            ErrorsLib.ZeroArgument("_excessRefundRecipient")
        );

        uint256 feePerRequest = TriggerableWithdrawals.getWithdrawalRequestFee();
        require(
            msg.value >= feePerRequest,
            ErrorsLib.InsufficientValidatorWithdrawalFee(msg.value, feePerRequest)
        );

        bytes32 pubkeyHash = keccak256(_pubkey);

        if (_amountInGwei == 0) {
            TriggerableWithdrawals.addFullWithdrawalRequests(_pubkey, feePerRequest);
            emit ValidatorFullExitTriggered(pubkeyHash, _pubkey);
        } else {
            TriggerableWithdrawals.addSingleWithdrawalRequest(_pubkey, _amountInGwei, feePerRequest);
            emit ValidatorPartialWithdrawalTriggered(
                pubkeyHash,
                _pubkey,
                uint256(_amountInGwei) * 1 gwei
            );
        }

        uint256 excess = msg.value - feePerRequest;
        if (excess > 0) {
            (bool success, ) = _excessRefundRecipient.call{value: excess}("");
            require(success, ErrorsLib.TransferFailed(_excessRefundRecipient, excess));
        }
    }

    /// @inheritdoc IEAGWithdrawVault
    function claimAll() external onlyEAGVaultOperator nonReentrant {
        IEAGVaultOperator.VaultData memory data = IEAGVaultOperator(_EAGVaultOperator).getVaultData(address(this));
        uint256 totalFees = data.accruedServiceFeeAmount + data.accruedContributionFeeAmount;
        uint256 totalAmountInVault = data.accruedRewards + data.accruedWithdrawnPrincipalAmount;
        uint256 distributableBalance = address(this).balance - _pendingOwnerBalance;
        require(
            totalAmountInVault >= totalFees && totalAmountInVault <= distributableBalance,
            ErrorsLib.InsufficientClaimableBalance(totalAmountInVault, totalFees)
        );

        uint256 serviceFee = data.accruedServiceFeeAmount;
        uint256 contributionFee = data.accruedContributionFeeAmount;

        if (serviceFee > 0) {
            (bool s, ) = payable(data.serviceFeeReceiver).call{value: serviceFee}("");
            require(s, ErrorsLib.TransferFailed(data.serviceFeeReceiver, serviceFee));
        }
        if (contributionFee > 0) {
            (bool s, ) = payable(data.contributionFeeReceiver).call{value: contributionFee}("");
            require(s, ErrorsLib.TransferFailed(data.contributionFeeReceiver, contributionFee));
        }

        uint256 userAmount = totalAmountInVault - serviceFee - contributionFee;
        if (userAmount > 0) {
            (bool s, ) = payable(_owner).call{value: userAmount, gas: ConstantLib.OWNER_TRANSFER_GAS_LIMIT}("");
            if (s) {
                emit VaultClaimedAll(userAmount, serviceFee, contributionFee);
            } else {
                _pendingOwnerBalance += userAmount;
                emit VaultClaimedAll(0, serviceFee, contributionFee);
                emit OwnerTransferDeferred(_owner, userAmount);
            }
        } else {
            emit VaultClaimedAll(0, serviceFee, contributionFee);
        }
    }

    // ═══════════════════════════════════════════
    //       OWNER: PULL-BASED WITHDRAWAL
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGWithdrawVault
    function withdrawOwnerBalance() external onlyOwner nonReentrant {
        uint256 amount = _pendingOwnerBalance;
        require(amount > 0, ErrorsLib.ZeroArgument("_pendingOwnerBalance"));
        _pendingOwnerBalance = 0;
        (bool s, ) = payable(_owner).call{value: amount}("");
        require(s, ErrorsLib.TransferFailed(_owner, amount));
        emit OwnerBalanceWithdrawn(_owner, amount);
    }

    // ═══════════════════════════════════════════
    //       OWNER: OWNERSHIP MANAGEMENT
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGWithdrawVault
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), ErrorsLib.ZeroArgument("_newOwner"));
        _pendingOwner = _newOwner;
        emit OwnershipTransferStarted(_owner, _newOwner);
    }

    /// @inheritdoc IEAGWithdrawVault
    function acceptOwnership() external nonReentrant {
        require(msg.sender == _pendingOwner, ErrorsLib.SenderNotPendingOwner());
        address prev = _owner;
        address next = _pendingOwner;
        _owner = next;
        _pendingOwner = address(0);

        address router = VAULT_FACTORY.authorizedDeployer();
        IEAGStakingRouter(router).onVaultOwnerChanged(prev, next);

        emit OwnershipTransferred(prev, next);
    }

    /// @inheritdoc IEAGWithdrawVault
    function cancelOwnershipTransfer() external onlyOwner {
        _pendingOwner = address(0);
        emit OwnershipTransferCanceled(_owner);
    }

    /// @inheritdoc IEAGWithdrawVault
    function renounceOwnership() external view onlyOwner {
        revert ErrorsLib.RenouncementNotAllowed();
    }

    // ═══════════════════════════════════════════
    //        OWNER: ASSET RECOVERY
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGWithdrawVault
    function collectERC20(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        require(_token != address(0), ErrorsLib.ZeroArgument("_token"));
        require(_recipient != address(0), ErrorsLib.ZeroArgument("_recipient"));
        require(_amount > 0, ErrorsLib.ZeroArgument("_amount"));
        require(_token != ConstantLib.ETH_SENTINEL, ErrorsLib.EthCollectionNotAllowed());
        SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
    }
}
