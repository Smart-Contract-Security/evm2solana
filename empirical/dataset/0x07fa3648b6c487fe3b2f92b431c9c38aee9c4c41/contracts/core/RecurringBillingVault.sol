// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./FeeManager.sol";

contract RecurringBillingVault is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    FeeManager public feeManager;
    address    public operator;

    struct Authorization {
        address  customer;
        address  merchant;
        bytes32  merchantId;
        address  token;       // ERC-20 address; WBNB/WETH for native subscriptions
        uint256  authorizedAt;
        bool     active;
    }

    mapping(bytes32 => Authorization) private _authorizations;

    event Authorized(
        bytes32 indexed subscriptionId,
        address indexed customer,
        address indexed merchant,
        bytes32  merchantId,
        address  token
    );
    event Pulled(
        bytes32 indexed subscriptionId,
        address indexed customer,
        bytes32  invoiceId,
        uint256  grossAmount,
        uint256  fee,
        uint256  merchantAmount
    );
    event Deactivated(bytes32 indexed subscriptionId);
    event OperatorUpdated(address oldOperator, address newOperator);

    error AlreadyAuthorized(bytes32 subscriptionId);
    error AuthorizationNotFound(bytes32 subscriptionId);
    error AuthorizationNotActive(bytes32 subscriptionId);
    error CustomerMismatch(bytes32 subscriptionId);
    error ZeroAmount();
    error NotOperator();
    error NotOperatorOrOwner();

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier onlyOperatorOrOwner() {
        if (msg.sender != operator && msg.sender != owner()) revert NotOperatorOrOwner();
        _;
    }

    constructor(address _operator, address _feeManager) Ownable(msg.sender) {
        operator   = _operator;
        feeManager = FeeManager(_feeManager);
    }

    // ── Customer-facing (called during checkout) ─────────────────────────────

    function authorize(
        bytes32 subscriptionId,
        address merchant,
        bytes32 merchantId,
        address token
    ) external whenNotPaused {
        if (_authorizations[subscriptionId].authorizedAt != 0)
            revert AlreadyAuthorized(subscriptionId);

        _authorizations[subscriptionId] = Authorization({
            customer:     msg.sender,
            merchant:     merchant,
            merchantId:   merchantId,
            token:        token,
            authorizedAt: block.timestamp,
            active:       true
        });

        emit Authorized(subscriptionId, msg.sender, merchant, merchantId, token);
    }

    // ── Operator-facing ──────────────────────────────────────────────────────

    function pull(
        bytes32 subscriptionId,
        address customer,
        uint256 amount,
        bytes32 invoiceId
    ) external onlyOperator nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        Authorization storage auth = _authorizations[subscriptionId];
        if (auth.authorizedAt == 0) revert AuthorizationNotFound(subscriptionId);
        if (!auth.active)           revert AuthorizationNotActive(subscriptionId);
        if (auth.customer != customer) revert CustomerMismatch(subscriptionId);

        (uint256 fee, uint256 merchantAmount) = feeManager.computeFee(auth.merchantId, amount);

        IERC20(auth.token).safeTransferFrom(customer, feeManager.feeRecipient(), fee);
        IERC20(auth.token).safeTransferFrom(customer, auth.merchant, merchantAmount);

        emit Pulled(subscriptionId, customer, invoiceId, amount, fee, merchantAmount);
    }

    // ── Only operator or owner can deactivate (not the customer) ────────────

    function deactivate(bytes32 subscriptionId) external onlyOperatorOrOwner {
        Authorization storage auth = _authorizations[subscriptionId];
        if (auth.authorizedAt == 0) revert AuthorizationNotFound(subscriptionId);
        auth.active = false;
        emit Deactivated(subscriptionId);
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    function setOperator(address _operator) external onlyOwner {
        emit OperatorUpdated(operator, _operator);
        operator = _operator;
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        feeManager = FeeManager(_feeManager);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ── Views ────────────────────────────────────────────────────────────────

    function getAuthorization(bytes32 subscriptionId)
        external view returns (Authorization memory)
    {
        return _authorizations[subscriptionId];
    }
}
