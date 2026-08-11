// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./BridgeVault.sol";

/// @title BridgeRouter — user-facing entry point for the cross-chain bridge
/// @notice Accepts native ETH deposits for cross-chain bridging to destination chains and
///         finalizes withdrawals back
contract BridgeRouter is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    error ZeroAddress();
    error NotAnAdmin();
    error NotAManager();
    error ZeroAmount();
    error FeeTooHigh();
    error AmountBelowMinimum();
    error NotARelayer();
    error ChainNotSupported();
    error InvalidCryptoFeeAmount();
    error InvalidMessageId();
    error ETHTransferFailed();
    error NotWhitelistedDepositor();
    error DepositsPaused();
    error WithdrawalsPaused();
    error WouldDrainFees();
    error DirectETHDepositDisabled();
    error CannotRevokeLastAdmin();

    /// @notice Maximum allowed proportional protocol fee in basis points (1 bp = 0.01%)
    uint16 public constant MAX_PROTOCOL_FEE_BPS = 1_000; // 10%
    /// @notice Role for operational configuration and pause controls
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Role allowed to finalize withdrawals
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @notice Emitted when the fixed and proportional deposit fees are updated
    event FeesUpdated(uint256 cryptoFee, uint16 protocolFeeBps);

    /// @notice Emitted when the minimum bridged amount is updated
    event LimitsUpdated(uint256 minAmount);

    /// @notice Emitted when accumulated fees are transferred to a recipient
    event FeeCollected(uint256 amount, address indexed recipient);

    /// @notice Emitted when assets are rescued from the router
    event SweepTokens(address indexed token, uint256 amount, address indexed recipient);

    /// @notice Emitted when active destination configuration is updated
    event TokenMappingUpdated(uint256 indexed dstChainID, bytes32 dstToken);

    /// @notice Emitted when an address is added to the depositor whitelist
    event WhitelistDepositorAdded(address indexed depositor);

    /// @notice Emitted when an address is removed from the depositor whitelist
    event WhitelistDepositorRemoved(address indexed depositor);

    /// @notice Emitted when deposit pause state is updated
    event DepositsPauseUpdated(bool paused);

    /// @notice Emitted when withdrawal pause state is updated
    event WithdrawalsPauseUpdated(bool paused);

    /// @notice Reference to the vault contract that custodies bridged ETH
    BridgeVault public immutable vault;

    /// @dev Addresses permitted to call deposit()
    EnumerableSet.AddressSet private _whitelist;

    /// @notice Fixed fee in wei charged on every deposit (kept in the router)
    uint256 public cryptoFee;
    /// @notice Minimum deposit amount after all fees
    uint256 public minAmount;
    /// @notice Accumulated fees (cryptoFee + protocolFee), held in the router
    uint256 public feeBalance;

    /// @notice Active destination chain
    uint256 public dstChainID;

    /// @notice Active destination token
    bytes32 public dstOutputToken;

    /// @notice When true, deposit() is disabled
    bool public depositsPaused;
    /// @notice When true, finalizeWithdraw() is disabled
    bool public withdrawalsPaused;
    /// @notice Proportional protocol fee in basis points (1 bp = 0.01%)
    uint16 public protocolFeeBps;

    /// @notice Reject direct ETH transfers to the router
    /// @dev All normal inflows must use deposit(), and fee accounting is tracked in feeBalance
    receive() external payable {
        revert DirectETHDepositDisabled();
    }

    /// @param _vault   Address of the deployed BridgeVault
    /// @param _admin   Initial DEFAULT_ADMIN_ROLE holder
    /// @param _relayers Addresses granted RELAYER_ROLE at deployment
    /// @param _initialCryptoFee Initial fixed fee in wei
    /// @param _initialProtocolFeeBps Initial protocol fee in basis points (max 1000 = 10%)
    /// @param _initialMinAmount Initial minimum deposit amount after fees
    constructor(
        address _vault,
        address _admin,
        address[] memory _relayers,
        uint256 _initialCryptoFee,
        uint16 _initialProtocolFeeBps,
        uint256 _initialMinAmount
    ) {
        if (_vault == address(0) || _admin == address(0)) {
            revert ZeroAddress();
        }
        if (_initialProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) {
            revert FeeTooHigh();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        vault = BridgeVault(payable(_vault));
        cryptoFee = _initialCryptoFee;
        protocolFeeBps = _initialProtocolFeeBps;
        minAmount = _initialMinAmount;

        uint256 length = _relayers.length;
        for (uint256 i; i < length; ++i) {
            if (_relayers[i] == address(0)) revert ZeroAddress();
            _grantRole(RELAYER_ROLE, _relayers[i]);
        }
    }

    /// @notice Deposit native ETH to bridge to destination chain
    /// @dev msg.value must be > cryptoFee. bridgeAmount = msg.value - cryptoFee - protocolFee
    /// @param _recipient Destination recipient encoded as bytes
    function deposit(bytes calldata _recipient)
        external
        payable
        whenDepositsNotPaused
        nonReentrant
        returns (bytes32 messageId)
    {
        if (!_whitelist.contains(msg.sender)) {
            revert NotWhitelistedDepositor();
        }

        uint256 _dstChainId = dstChainID;

        bytes32 _dstOutputToken = dstOutputToken;
        if (_dstChainId == 0 || _dstOutputToken == bytes32(0)) {
            revert ChainNotSupported();
        }

        if (msg.value <= cryptoFee) {
            revert InvalidCryptoFeeAmount();
        }

        uint256 depositAmount = msg.value - cryptoFee;

        uint256 protocolFee = _calculateFee(depositAmount);

        uint256 amountAfterFees = depositAmount - protocolFee;

        if (amountAfterFees < minAmount) {
            revert AmountBelowMinimum();
        }

        uint256 totalFees = cryptoFee + protocolFee;
        if (totalFees > 0) {
            feeBalance += totalFees;
        }

        messageId = vault.deposit{value: amountAfterFees}(msg.sender, _dstChainId, _dstOutputToken, _recipient);
    }

    /// @notice Complete a bridge withdrawal by releasing ETH from the vault
    /// @dev Only callable by RELAYER_ROLE. Each messageId can only be finalized once
    /// @param _messageId Unique cross-chain message
    /// @param _recipient address to receive the ETH
    /// @param _amount    Wei to release from the vault
    function finalizeWithdraw(bytes32 _messageId, address _recipient, uint256 _amount)
        external
        whenWithdrawalsNotPaused
        onlyRelayer(msg.sender)
        nonReentrant
    {
        if (_messageId == bytes32(0)) {
            revert InvalidMessageId();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }

        vault.release(_messageId, _recipient, _amount);
    }

    // reference to https://github.com/OpenZeppelin/openzeppelin-contracts/pull/3347/
    modifier onlyAdmin() {
        _checkIsAdmin();
        _;
    }

    modifier onlyManagerOrAdmin() {
        _checkIsManagerOrAdmin();
        _;
    }

    modifier onlyRelayer(address _relayer) {
        _checkIsRelayer(_relayer);
        _;
    }

    modifier whenDepositsNotPaused() {
        if (depositsPaused) revert DepositsPaused();
        _;
    }

    modifier whenWithdrawalsNotPaused() {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        _;
    }

    /// @notice Pause deposits
    function pauseDeposits() external onlyManagerOrAdmin {
        depositsPaused = true;
        emit DepositsPauseUpdated(true);
    }

    /// @notice Resume deposits
    function unpauseDeposits() external onlyAdmin {
        depositsPaused = false;
        emit DepositsPauseUpdated(false);
    }

    /// @notice Pause withdrawals
    function pauseWithdrawals() external onlyManagerOrAdmin {
        withdrawalsPaused = true;
        emit WithdrawalsPauseUpdated(true);
    }

    /// @notice Resume withdrawals
    function unpauseWithdrawals() external onlyAdmin {
        withdrawalsPaused = false;
        emit WithdrawalsPauseUpdated(false);
    }

    /// @notice Update the fixed crypto fee and proportional protocol fee
    /// @param _newCryptoFee      New fixed fee in wei
    /// @param _newProtocolFeeBps New proportional fee in basis points (max 1000 = 10%)
    function setFees(uint256 _newCryptoFee, uint16 _newProtocolFeeBps) external onlyManagerOrAdmin {
        if (_newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) {
            revert FeeTooHigh();
        }
        cryptoFee = _newCryptoFee;
        protocolFeeBps = _newProtocolFeeBps;
        emit FeesUpdated(_newCryptoFee, _newProtocolFeeBps);
    }

    /// @notice Update the minimum deposit amount (after fees)
    /// @param _newMinAmount New minimum amount after both fees collected
    function setMinAmount(uint256 _newMinAmount) external onlyManagerOrAdmin {
        minAmount = _newMinAmount;
        emit LimitsUpdated(_newMinAmount);
    }

    /// @notice Set active destination chain and destination token
    /// @dev Setting _dstToken to bytes32(0) disables deposits until reconfigured
    /// @param _dstChainID Destination chain
    /// @param _dstToken Destination token
    function setDestination(uint256 _dstChainID, bytes32 _dstToken) external onlyManagerOrAdmin {
        dstChainID = _dstChainID;
        dstOutputToken = _dstToken;
        emit TokenMappingUpdated(_dstChainID, _dstToken);
    }

    /// @notice Add an address to the depositor whitelist
    /// @param _depositor Address to authorize for deposit()
    function addToWhitelist(address _depositor) external onlyManagerOrAdmin {
        if (_depositor == address(0)) {
            revert ZeroAddress();
        }
        _whitelist.add(_depositor);
        emit WhitelistDepositorAdded(_depositor);
    }

    /// @notice Remove an address from the depositor whitelist
    /// @param _depositor Address to remove from whitelist
    function removeFromWhitelist(address _depositor) external onlyManagerOrAdmin {
        _whitelist.remove(_depositor);
        emit WhitelistDepositorRemoved(_depositor);
    }

    /// @notice Check if an address is whitelisted for deposits
    /// @return True if the address is currently whitelisted
    function isWhitelisted(address _addr) external view returns (bool) {
        return _whitelist.contains(_addr);
    }

    /// @notice Return all whitelisted depositor addresses
    /// @return Array of all whitelisted depositor addresses
    function getWhitelist() external view returns (address[] memory) {
        return _whitelist.values();
    }

    /// @notice Collect all accumulated fees (cryptoFee + protocolFee) from the router
    /// @dev Transfers only the ETH held by this router contract and resets feeBalance to zero
    /// @param _recipient Address to receive the fee ETH
    function collectFee(address _recipient) external onlyAdmin nonReentrant {
        if (_recipient == address(0)) {
            revert ZeroAddress();
        }

        uint256 _amount = feeBalance;
        if (_amount == 0) {
            revert ZeroAmount();
        }
        feeBalance = 0;

        (bool success,) = payable(_recipient).call{value: _amount}("");
        if (!success) {
            revert ETHTransferFailed();
        }

        emit FeeCollected(_amount, _recipient);
    }

    /// @notice Rescue stuck ETH or accidentally-sent ERC20 tokens from the router
    /// @dev Sweeping native ETH is blocked if it would reduce the reserved fee balance
    /// @param _token     Token address (address(0) for native ETH)
    /// @param _amount    Amount to sweep
    /// @param _recipient Destination address
    function sweepTokens(address _token, uint256 _amount, address _recipient) external onlyAdmin nonReentrant {
        if (_recipient == address(0)) {
            revert ZeroAddress();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }

        if (_token == address(0)) {
            if (address(this).balance < feeBalance + _amount) {
                revert WouldDrainFees();
            }
            (bool success,) = payable(_recipient).call{value: _amount}("");
            if (!success) {
                revert ETHTransferFailed();
            }
        } else {
            IERC20(_token).safeTransfer(_recipient, _amount);
        }

        emit SweepTokens(_token, _amount, _recipient);
    }

    function _calculateFee(uint256 _amount) internal view returns (uint256) {
        return (_amount * protocolFeeBps) / 10_000;
    }

    /**
     * @notice Used in modifiers
     * @dev Function to check if address is belongs to relayer role
     */
    function _checkIsRelayer(address _relayer) internal view {
        if (!hasRole(RELAYER_ROLE, _relayer)) {
            revert NotARelayer();
        }
    }

    /**
     * @notice Used in modifiers
     * @dev Function to check if address is belongs to manager or admin role
     */
    function _checkIsManagerOrAdmin() internal view {
        if (!(hasRole(MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))) {
            revert NotAManager();
        }
    }

    /**
     * @notice Used in modifiers
     * @dev Function to check if address is belongs to default admin role
     */
    function _checkIsAdmin() internal view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAnAdmin();
        }
    }

    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE && hasRole(role, account) && getRoleMemberCount(DEFAULT_ADMIN_ROLE) <= 1) {
            revert CannotRevokeLastAdmin();
        }
        return super._revokeRole(role, account);
    }
}
