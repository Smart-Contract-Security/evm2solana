// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./FeeManager.sol";
import "./MerchantRegistry.sol";

contract PaymentRouter is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    FeeManager       public feeManager;
    MerchantRegistry public merchantRegistry;
    uint256          public immutable CHAIN_ID;

    mapping(address  => bool) public supportedTokens;
    mapping(bytes32  => bool) public processedInvoices;

    event PaymentReceived(
        bytes32 indexed merchantId,
        bytes32 indexed invoiceId,
        address indexed customer,
        address  token,
        uint256  grossAmount,
        uint256  fee,
        uint256  merchantAmount,
        uint256  chainId
    );
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event FeeManagerUpdated(address oldFeeManager, address newFeeManager);

    error UnsupportedToken(address token);
    error InvoiceAlreadyProcessed(bytes32 invoiceId);
    error MerchantNotActive(bytes32 merchantId);
    error ZeroAmount();
    error WrongChain(uint256 expected, uint256 actual);
    error NativeTransferFailed();

    constructor(
        address _feeManager,
        address _merchantRegistry,
        address[] memory _initialTokens
    ) Ownable(msg.sender) {
        feeManager       = FeeManager(_feeManager);
        merchantRegistry = MerchantRegistry(_merchantRegistry);
        CHAIN_ID         = block.chainid;
        for (uint256 i = 0; i < _initialTokens.length; i++) {
            supportedTokens[_initialTokens[i]] = true;
            emit TokenAdded(_initialTokens[i]);
        }
    }

    // ── ERC-20 payment ──────────────────────────────────────────────────────

    function pay(
        bytes32 merchantId,
        bytes32 invoiceId,
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        if (block.chainid != CHAIN_ID) revert WrongChain(CHAIN_ID, block.chainid);
        if (!supportedTokens[token])   revert UnsupportedToken(token);
        if (amount == 0)               revert ZeroAmount();
        if (!merchantRegistry.isMerchantActive(merchantId)) revert MerchantNotActive(merchantId);
        if (processedInvoices[invoiceId]) revert InvoiceAlreadyProcessed(invoiceId);

        processedInvoices[invoiceId] = true;

        (uint256 fee, uint256 merchantAmount) = feeManager.computeFee(merchantId, amount);
        address settlementWallet = merchantRegistry.getMerchantWallet(merchantId);

        IERC20(token).safeTransferFrom(msg.sender, feeManager.feeRecipient(), fee);
        IERC20(token).safeTransferFrom(msg.sender, settlementWallet, merchantAmount);

        emit PaymentReceived(merchantId, invoiceId, msg.sender, token, amount, fee, merchantAmount, CHAIN_ID);
    }

    // ── Native token payment (BNB / ETH) ────────────────────────────────────

    function payNative(
        bytes32 merchantId,
        bytes32 invoiceId
    ) external payable nonReentrant whenNotPaused {
        if (block.chainid != CHAIN_ID) revert WrongChain(CHAIN_ID, block.chainid);
        if (msg.value == 0)            revert ZeroAmount();
        if (!merchantRegistry.isMerchantActive(merchantId)) revert MerchantNotActive(merchantId);
        if (processedInvoices[invoiceId]) revert InvoiceAlreadyProcessed(invoiceId);

        processedInvoices[invoiceId] = true;

        (uint256 fee, uint256 merchantAmount) = feeManager.computeFee(merchantId, msg.value);
        address settlementWallet = merchantRegistry.getMerchantWallet(merchantId);

        (bool feeOk,) = feeManager.feeRecipient().call{value: fee}("");
        if (!feeOk) revert NativeTransferFailed();

        (bool merchantOk,) = settlementWallet.call{value: merchantAmount}("");
        if (!merchantOk) revert NativeTransferFailed();

        emit PaymentReceived(merchantId, invoiceId, msg.sender, address(0), msg.value, fee, merchantAmount, CHAIN_ID);
    }

    // ── Admin ───────────────────────────────────────────────────────────────

    function addToken(address token) external onlyOwner {
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function removeToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        emit FeeManagerUpdated(address(feeManager), _feeManager);
        feeManager = FeeManager(_feeManager);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    receive() external payable {}
}
