// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Vault contract to hold native ETH for the BridgeRouter
/// @notice This contract is used to securely store ETH that is being bridged
/// @dev The contract is separated from the router for security isolation
contract BridgeVault is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error NotRouter();
    error NotAnAdmin();
    error DirectETHDepositDisabled();
    error DailyWithdrawLimitExceeded();
    error ETHTransferFailed();
    error CannotRevokeLastAdmin();
    error MessageAlreadyProcessed();

    /// @notice Emitted when ETH is locked
    /// @param messageId Unique bridge message
    /// @param bridgeAmount Net bridged amount in wei
    /// @param srcChainID Source chain
    /// @param dstChainID Destination chain 
    /// @param dstOutputToken Destination token
    /// @param recipient Destination recipient
    event Deposit(
        bytes32 indexed messageId,
        uint256 bridgeAmount,
        uint256 srcChainID,
        uint256 indexed dstChainID,
        bytes32 dstOutputToken,
        bytes indexed recipient
    );

    /// @notice Emitted when ETH is released for a cross-chain withdrawal
    /// @param messageId Unique bridge message
    /// @param recipient Recipient address on the destination chain
    /// @param amount Released amount in wei
    event Withdraw(bytes32 indexed messageId, address indexed recipient, uint256 amount);

    /// @notice Emitted when daily withdrawal limit is updated
    /// @param limit New daily withdrawal limit in wei, where zero disables the check
    event DailyWithdrawLimitUpdated(uint256 limit);

    /// @notice Emitted when the authorized router is updated
    event RouterUpdated(address indexed newRouter);

    /// @notice Emitted when ERC20 tokens are rescued from the vault
    event Swept(address indexed token, address indexed to, uint256 amount);

    /// @notice Authorized router that can call deposit() and release()
    address public router;

    /// @notice Replay-protection: messageId => already released
    mapping(bytes32 => bool) public processedMessages;

    /// @notice Increasing nonce used in messageId
    uint256 public nonce;

    /// @notice Optional max ETH amount that can be released per UTC day
    /// @dev 0 means disabled (no limit enforced)
    uint256 public dailyWithdrawLimit;

    /// @dev dayIndex => withdrawnAmount
    mapping(uint256 => uint256) public withdrawnPerDay;

    /// @notice Initialize vault admin permissions
    constructor(address _admin) {
        if (_admin == address(0)) {
            revert ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Reject direct ETH transfers to the vault
    /// @dev Bridge inflows must come through deposit() from the authorized router
    receive() external payable {
        revert DirectETHDepositDisabled();
    }

    /// @notice Lock bridged ETH and emit canonical deposit metadata for relayers
    /// @dev Callable only by the configured router
    /// @param _sender Original EVM depositor address
    /// @param _dstChainID Destination chain
    /// @param _dstOutputToken Destination token
    /// @param _recipient Recipient on the destination chain
    /// @return messageId Unique message identifier used for idempotent processing
    function deposit(address _sender, uint256 _dstChainID, bytes32 _dstOutputToken, bytes calldata _recipient)
        external
        payable
        onlyRouter
        returns (bytes32 messageId)
    {
        if (msg.value == 0) {
            revert ZeroAmount();
        }

        messageId = _nextMessageId(_sender, msg.value, _dstChainID, _dstOutputToken, _recipient);

        emit Deposit(messageId, msg.value, block.chainid, _dstChainID, _dstOutputToken, _recipient);
    }

    modifier onlyRouter() {
        _checkIsRouter();
        _;
    }

    modifier onlyAdmin() {
        _checkIsAdmin();
        _;
    }

    /// @notice Set the router authorized to call deposit() and release()
    function setRouter(address _newRouter) external onlyAdmin {
        if (_newRouter == address(0)) {
            revert ZeroAddress();
        }
        router = _newRouter;
        emit RouterUpdated(_newRouter);
    }

    /// @notice Set daily ETH release limit (0 disables the check)
    function setDailyWithdrawLimit(uint256 _limit) external onlyAdmin {
        dailyWithdrawLimit = _limit;
        emit DailyWithdrawLimitUpdated(_limit);
    }

    /// @notice Release ETH for a finalized burn message
    /// @dev Enforces exactly-once processing by messageId
    function release(bytes32 _messageId, address _to, uint256 _amount) external onlyRouter nonReentrant {
        if (_to == address(0)) {
            revert ZeroAddress();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }
        if (processedMessages[_messageId]) {
            revert MessageAlreadyProcessed();
        }
        processedMessages[_messageId] = true;

        // Daily limit applies to all releases from the vault

        uint256 limit = dailyWithdrawLimit;
        if (limit != 0) {
            uint256 dayIndex = block.timestamp / 1 days;

            uint256 withdrawn = withdrawnPerDay[dayIndex];
            if (withdrawn + _amount > limit) {
                revert DailyWithdrawLimitExceeded();
            }
            withdrawnPerDay[dayIndex] = withdrawn + _amount;
        }

        (bool success,) = payable(_to).call{value: _amount}("");
        if (!success) {
            revert ETHTransferFailed();
        }

        emit Withdraw(_messageId, _to, _amount);
    }

    /// @notice Rescue accidentally-sent ERC20 tokens. Native ETH cannot be swept
    function sweep(address _token, address _to, uint256 _amount) external onlyAdmin nonReentrant {
        if (_to == address(0)) {
            revert ZeroAddress();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit Swept(_token, _to, _amount);
    }

    /**
     * @notice Used in modifiers
     * @dev Function to check if caller is router
     */
    function _checkIsRouter() internal view {
        if (msg.sender != router) {
            revert NotRouter();
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

    function _nextMessageId(
        address _sender,
        uint256 _amount,
        uint256 _dstChainID,
        bytes32 _dstOutputToken,
        bytes memory _recipient
    ) internal returns (bytes32) {
        uint256 currentNonce = nonce++;
        return keccak256(
            abi.encodePacked(
                _sender,
                block.chainid,
                currentNonce,
                _amount,
                _dstChainID,
                _dstOutputToken,
                _recipient
            )
        );
    }

    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE && hasRole(role, account) && getRoleMemberCount(DEFAULT_ADMIN_ROLE) <= 1) {
            revert CannotRevokeLastAdmin();
        }
        return super._revokeRole(role, account);
    }
}
