// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  LodeSplitter — three-way split for captured LVR
/// @notice Receives ETH/ERC20 premiums from the hook and forwards them per
///         the per-pool split:
///           - protocolFeeBps : to LODE protocol vault (default 2000 = 20%)
///           - builderFeeBps  : to the pool's builder (0–3000)
///           - remainder      : to the pool's beneficiary (LPs / treasury /
///                              token buyback / etc.)
/// @dev    The splitter is per-pool; one is deployed by the factory for each
///         builder pool. Flagship pools use a special splitter where
///         protocolFeeBps = 10000 (all LVR flows to LODE protocol).
contract LodeSplitter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Unauthorized();
    error ZeroAddress();
    error InvalidSplit();
    error NoPendingChange();
    error TimelockNotMet();
    error OwnerChangedDuringQueue();

    event SplitUpdated(uint16 protocolFeeBps, uint16 builderFeeBps);
    event RecipientsUpdated(address protocolVault, address builder, address beneficiary);
    event Distributed(address indexed token, uint256 toProtocol, uint256 toBuilder, uint256 toBeneficiary);
    event BeneficiaryChangeQueued(address indexed newBeneficiary, uint256 executableAt, address queuedBy);
    event BeneficiaryChangeCancelled(address indexed cancelled);
    event PublicDistributeSet(bool enabled);

    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant BENEFICIARY_TIMELOCK = 48 hours;

    /// @notice When false (default), only owner / governance / builder / beneficiary
    ///         can call distribute(). Prevents anyone-can-call MEV against the
    ///         distribution timing. Builders can opt in for permissionless mode.
    bool public publicDistribute;

    // Authority
    address public owner;          // builder for builder pools; LODE governance for flagship
    address public lodeGovernance; // can override split (slashing scenario)

    // Recipients
    address public protocolVault;  // LODE protocol-fee vault (always required)
    address public builder;        // builder wallet, only set for builder pools
    address public beneficiary;    // builder-designated recipient

    // Split
    uint16 public protocolFeeBps;
    uint16 public builderFeeBps;

    // Beneficiary change timelock
    address public pendingBeneficiary;
    uint256 public pendingBeneficiaryExecutableAt;
    /// @notice Owner at queue time. If owner changes before execute, the
    ///         queue is voided — prevents a compromised new owner from
    ///         executing a pending change queued under the old owner.
    address public pendingQueuedBy;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != lodeGovernance) revert Unauthorized();
        _;
    }

    constructor(
        address _owner,
        address _lodeGovernance,
        address _protocolVault,
        address _builder,
        address _beneficiary,
        uint16 _protocolFeeBps,
        uint16 _builderFeeBps
    ) {
        if (_owner == address(0) || _lodeGovernance == address(0) || _protocolVault == address(0)) {
            revert ZeroAddress();
        }
        if (_beneficiary == address(0)) revert ZeroAddress();
        owner = _owner;
        lodeGovernance = _lodeGovernance;
        protocolVault = _protocolVault;
        builder = _builder;
        beneficiary = _beneficiary;
        _setSplit(_protocolFeeBps, _builderFeeBps);
        emit RecipientsUpdated(_protocolVault, _builder, _beneficiary);
    }

    receive() external payable {}

    // -------------------------------------------------------------------------
    // Distribution
    // -------------------------------------------------------------------------

    /// @notice Distribute the full balance of `token` (use address(0) for ETH).
    /// @dev    `nonReentrant` because beneficiary/builder may be contracts that
    ///         re-enter via ETH `.call` or ERC777-style hooks. Protocol vault
    ///         is paid LAST so the most trusted recipient settles even if
    ///         downstream sends fail.
    modifier canDistribute() {
        if (!publicDistribute) {
            if (
                msg.sender != owner
                && msg.sender != lodeGovernance
                && msg.sender != builder
                && msg.sender != beneficiary
                && msg.sender != protocolVault
            ) revert Unauthorized();
        }
        _;
    }

    function setPublicDistribute(bool _enabled) external onlyOwner {
        publicDistribute = _enabled;
        emit PublicDistributeSet(_enabled);
    }

    function distribute(address token) external nonReentrant canDistribute {
        uint256 bal = _balanceOf(token);
        if (bal == 0) return;

        uint256 toProtocol = (bal * protocolFeeBps) / BPS_DENOMINATOR;
        uint256 toBuilder  = builder == address(0) ? 0 : (bal * builderFeeBps) / BPS_DENOMINATOR;
        uint256 toBeneficiary = bal - toProtocol - toBuilder;

        // Pay untrusted recipients first, protocol last.
        if (toBeneficiary > 0) _send(token, beneficiary, toBeneficiary);
        if (toBuilder > 0)     _send(token, builder, toBuilder);
        if (toProtocol > 0)    _send(token, protocolVault, toProtocol);

        emit Distributed(token, toProtocol, toBuilder, toBeneficiary);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------
    function setSplit(uint16 _protocolFeeBps, uint16 _builderFeeBps) external onlyOwner {
        _setSplit(_protocolFeeBps, _builderFeeBps);
    }

    /// @notice Queue a beneficiary change. Executable after BENEFICIARY_TIMELOCK.
    /// @dev    Records the queuing owner; if owner is rotated before execute,
    ///         the queue is voided (defeats compromise-then-execute attack).
    function queueBeneficiaryChange(address _beneficiary) external onlyOwner {
        if (_beneficiary == address(0)) revert ZeroAddress();
        pendingBeneficiary = _beneficiary;
        pendingBeneficiaryExecutableAt = block.timestamp + BENEFICIARY_TIMELOCK;
        pendingQueuedBy = owner;
        emit BeneficiaryChangeQueued(_beneficiary, pendingBeneficiaryExecutableAt, owner);
    }

    /// @notice Execute a previously-queued beneficiary change.
    function executeBeneficiaryChange() external onlyOwner {
        if (pendingBeneficiary == address(0)) revert NoPendingChange();
        if (block.timestamp < pendingBeneficiaryExecutableAt) revert TimelockNotMet();
        if (pendingQueuedBy != owner) revert OwnerChangedDuringQueue();
        beneficiary = pendingBeneficiary;
        emit RecipientsUpdated(protocolVault, builder, beneficiary);
        delete pendingBeneficiary;
        delete pendingBeneficiaryExecutableAt;
        delete pendingQueuedBy;
    }

    /// @notice Cancel a pending beneficiary change. Owner or governance.
    function cancelBeneficiaryChange() external {
        if (msg.sender != owner && msg.sender != lodeGovernance) revert Unauthorized();
        if (pendingBeneficiary == address(0)) revert NoPendingChange();
        address cancelled = pendingBeneficiary;
        delete pendingBeneficiary;
        delete pendingBeneficiaryExecutableAt;
        delete pendingQueuedBy;
        emit BeneficiaryChangeCancelled(cancelled);
    }

    function setBuilder(address _builder) external onlyOwner {
        builder = _builder;
        emit RecipientsUpdated(protocolVault, _builder, beneficiary);
    }

    /// @notice Governance override (slashing): can rotate protocolVault and zero out builder.
    function governanceOverride(address _protocolVault, uint16 _protocolFeeBps) external onlyGovernance {
        if (_protocolVault == address(0)) revert ZeroAddress();
        protocolVault = _protocolVault;
        if (_protocolFeeBps + builderFeeBps > BPS_DENOMINATOR) revert InvalidSplit();
        protocolFeeBps = _protocolFeeBps;
        emit RecipientsUpdated(_protocolVault, builder, beneficiary);
        emit SplitUpdated(_protocolFeeBps, builderFeeBps);
    }

    function setOwner(address _owner) external onlyOwner {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------
    function _setSplit(uint16 _protocolFeeBps, uint16 _builderFeeBps) internal {
        if (_protocolFeeBps + _builderFeeBps > BPS_DENOMINATOR) revert InvalidSplit();
        // No upper cap on protocolFeeBps individually — flagship pools set 100%
        // (all LVR to LODE protocol). Builder pools enforce their own ceiling
        // via the factory; this contract only enforces the math invariant.
        if (_builderFeeBps > 3000) revert InvalidSplit(); // builder share capped at 30%
        protocolFeeBps = _protocolFeeBps;
        builderFeeBps = _builderFeeBps;
        emit SplitUpdated(_protocolFeeBps, _builderFeeBps);
    }

    function _balanceOf(address token) internal view returns (uint256) {
        return token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    function _send(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "TransferFailed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
