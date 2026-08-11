// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IComplianceRegistry} from "./IComplianceRegistry.sol";
import {MettaPayMilestoneEscrow} from "./MettaPayMilestoneEscrow.sol";

/**
 * @title MettaPayEscrowFactory
 * @notice One per chain. Owns the compliance officer allowlist (queried by every
 *         clone via IComplianceRegistry), the fee configuration, and the
 *         deterministic clone deploy entry point.
 *
 *         createEscrow(...) pulls funds from the buyer, deploys a CREATE2 clone
 *         of `implementation`, transfers the funds into it, and calls
 *         initialize(...) — all in a single tx (~45-90k gas + clone init).
 */
contract MettaPayEscrowFactory is IComplianceRegistry, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────
    // Config
    // ─────────────────────────────────────────────────────────────────────

    uint16 public constant MAX_FEE_BPS = 2000; // 20% hard cap

    address public immutable implementation;

    address public feeWallet;
    uint16  public depositFeeBps = 400;   // 4.00%
    uint16  public releaseFeeBps = 700;   // 7.00%
    uint16  public recallFeeBps  = 1500;  // 15.00%

    /// @notice Global officer allowlist. Any officer can act on ANY clone.
    mapping(address => bool) public override isCompliance;

    /// @notice dealId → clone address. Lets the backend recover the clone
    ///         even if it lost the receipt.
    mapping(bytes32 => address) public getClone;

    /// @notice Supported tokens per chain (mirrors escrow_supported_tokens
    ///         off-chain, but enforced on-chain as defense-in-depth).
    mapping(address => bool) public isSupportedToken;

    // ─────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────

    event FeeWalletUpdated(address indexed previous, address indexed current);
    event FeeBpsUpdated(uint16 deposit, uint16 release, uint16 recall);
    event OfficerAdded(address indexed officer);
    event OfficerRemoved(address indexed officer);
    event SupportedTokenAdded(address indexed token);
    event SupportedTokenRemoved(address indexed token);
    event EscrowCreated(
        bytes32 indexed dealId,
        address indexed escrow,
        address indexed buyer,
        address seller,
        address token,
        uint256 amount,
        address notifyOfficer
    );

    // ─────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error FeeTooHigh();
    error DealAlreadyExists();
    error TokenNotSupported();
    error NotEth();
    error AmountMismatch();

    // ─────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────

    constructor(address impl, address initialOwner, address initialFeeWallet, address initialOfficer)
        Ownable(initialOwner)
    {
        if (impl == address(0) || initialFeeWallet == address(0) || initialOfficer == address(0)) revert ZeroAddress();
        implementation = impl;
        feeWallet = initialFeeWallet;
        isCompliance[initialOfficer] = true;
        emit FeeWalletUpdated(address(0), initialFeeWallet);
        emit OfficerAdded(initialOfficer);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Owner admin
    // ─────────────────────────────────────────────────────────────────────

    function setFeeWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) revert ZeroAddress();
        emit FeeWalletUpdated(feeWallet, newWallet);
        feeWallet = newWallet;
    }

    function setFeeBps(uint16 deposit_, uint16 release_, uint16 recall_) external onlyOwner {
        if (deposit_ > MAX_FEE_BPS || release_ > MAX_FEE_BPS || recall_ > MAX_FEE_BPS) revert FeeTooHigh();
        depositFeeBps = deposit_;
        releaseFeeBps = release_;
        recallFeeBps  = recall_;
        emit FeeBpsUpdated(deposit_, release_, recall_);
    }

    function addCompliance(address officer) external onlyOwner {
        if (officer == address(0)) revert ZeroAddress();
        isCompliance[officer] = true;
        emit OfficerAdded(officer);
    }

    function removeCompliance(address officer) external onlyOwner {
        isCompliance[officer] = false;
        emit OfficerRemoved(officer);
    }

    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        isSupportedToken[token] = true;
        emit SupportedTokenAdded(token);
    }

    function removeSupportedToken(address token) external onlyOwner {
        isSupportedToken[token] = false;
        emit SupportedTokenRemoved(token);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────
    // Buyer: createEscrow (deploys a clone and funds it)
    // ─────────────────────────────────────────────────────────────────────

    function createEscrow(
        bytes32 dealId,
        address seller,
        address token,
        uint256 amount,
        address[] calldata cosigners,
        uint8 threshold,
        MettaPayMilestoneEscrow.MilestoneInput[] calldata milestones,
        address notifyOfficer
    ) external payable whenNotPaused returns (address escrow) {
        if (getClone[dealId] != address(0)) revert DealAlreadyExists();
        if (amount == 0) revert AmountMismatch();
        if (token != address(0) && !isSupportedToken[token]) revert TokenNotSupported();
        if (notifyOfficer != address(0) && !isCompliance[notifyOfficer]) revert ZeroAddress();

        // Deterministic clone — predictable address per dealId for off-chain UX.
        escrow = Clones.cloneDeterministic(implementation, dealId);
        getClone[dealId] = escrow;

        // Move the funds into the clone, then initialize.
        if (token == address(0)) {
            if (msg.value != amount) revert AmountMismatch();
        } else {
            if (msg.value != 0) revert NotEth();
            IERC20(token).safeTransferFrom(msg.sender, escrow, amount);
        }

        MettaPayMilestoneEscrow.InitParams memory p = MettaPayMilestoneEscrow.InitParams({
            dealId: dealId,
            buyer: msg.sender,
            seller: seller,
            token: token,
            amount: amount,
            cosigners: cosigners,
            threshold: threshold,
            milestones: milestones,
            notifyOfficer: notifyOfficer,
            feeWallet: feeWallet,
            depositFeeBps: depositFeeBps,
            releaseFeeBps: releaseFeeBps,
            recallFeeBps: recallFeeBps
        });

        // For native ETH, forward the value to the clone's initialize().
        if (token == address(0)) {
            MettaPayMilestoneEscrow(payable(escrow)).initialize{value: amount}(p);
        } else {
            MettaPayMilestoneEscrow(payable(escrow)).initialize(p);
        }

        emit EscrowCreated(dealId, escrow, msg.sender, seller, token, amount, notifyOfficer);
    }

    /// @notice Predict a clone address without deploying — useful for the UI
    ///         to render the pending escrow address before the user signs.
    function predictEscrowAddress(bytes32 dealId) external view returns (address) {
        return Clones.predictDeterministicAddress(implementation, dealId, address(this));
    }
}
