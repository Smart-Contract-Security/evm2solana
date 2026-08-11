//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SparseMerkleTree} from '@solarity-solidity-lib/libs/data-structures/SparseMerkleTree.sol';
import {DefiIdRegistrarBase} from 'contracts/defi-id/DefiIdRegistrarBase.sol';
import {DefiIdRegistrarWhitelist} from 'contracts/defi-id/DefiIdRegistrarWhitelist.sol';
import {LabelValidator} from 'contracts/libs/LabelValidator.sol';
import {SMTVerifier} from 'contracts/libs/SMTVerifier.sol';

/// @title DefiIdRegistrar
/// @notice Concrete DeFi ID registrar — public registration, renewal, and subname logic.
contract DefiIdRegistrar is DefiIdRegistrarWhitelist {
  using SafeERC20 for IERC20;

  constructor(
    address _wrapper,
    address _usdc,
    bytes32 _parentNode,
    address _owner,
    address _beneficiary,
    address _defaultResolver,
    uint256 _price3,
    uint256 _price45,
    uint256 _price67,
    bytes32 _excludedRoot
  )
    DefiIdRegistrarBase(
      _wrapper, _usdc, _parentNode, _owner, _beneficiary, _defaultResolver, _price3, _price45, _price67, _excludedRoot
    )
  {}

  /// @notice Register a new DeFi ID label. The caller becomes the owner of the wrapped name.
  /// @param label      The label to register (e.g. "alice" for alice.defi.com).
  /// @param cadence    Payment cadence (Annual or Monthly). Ignored for standard labels.
  /// @param duration   Term length in years (Annual) or months (Monthly). Ignored for standard labels.
  /// @param excludedProof SMT exclusion proof against the excluded-labels root.
  function register(
    string calldata label,
    PaymentCadence cadence,
    uint8 duration,
    SparseMerkleTree.Proof calldata excludedProof
  ) external nonReentrant {
    _requireNotPaused();
    LabelValidator.validateLabel(label);

    // SMT policy check — skipped when the excluded root is unset.
    if (excludedRoot != bytes32(0)) {
      bytes32 leafKey = keccak256(abi.encodePacked(label));
      require(SMTVerifier.verifyNonInclusion(excludedProof, excludedRoot, leafKey), LabelExcluded());
    }

    (uint256 cost, uint64 expiry, HandleClass handleClass) =
      _computeCostAndExpiry(bytes(label).length, cadence, duration);

    if (cost > 0) {
      USDC.safeTransferFrom(msg.sender, beneficiary, cost);
    }

    _issue(label, msg.sender, expiry, cost, handleClass);
  }

  /// @notice Renew an active or grace-period DeFi ID label. Anyone can renew an active name, but only the current owner can renew during the grace period after expiry.
  /// @param label    The label to renew (e.g. "alice" for alice.defi.com).
  /// @param cadence  Payment cadence (Annual or Monthly). Ignored for standard labels.
  /// @param duration Term length in years (Annual) or months (Monthly). Ignored for standard labels.
  function renew(
    string calldata label,
    PaymentCadence cadence,
    uint8 duration
  ) external nonReentrant {
    _requireNotPaused();

    bytes32 labelhash = keccak256(bytes(label));
    bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, labelhash));

    uint64 currentExpiry = nameInfoOf[node].expiry;

    // After grace period → name is expired, not renewable.
    require(currentExpiry + GRACE_PERIOD >= block.timestamp, NameExpired());

    // During grace period → only the current owner can renew.
    if (currentExpiry < block.timestamp) {
      (address nameOwner,,) = WRAPPER.getData(uint256(node));
      require(nameOwner == msg.sender, OnlyOwnerCanRenewInGrace());
    }

    uint256 len = bytes(label).length;
    uint256 cost;
    uint64 newExpiry;

    if (len >= 8) {
      // Standard: free, extends by 1 year from current expiry.
      cost = 0;
      newExpiry = currentExpiry + 365 days;
    } else {
      // Premium: paid at current rates, cadence/duration determine extension.
      cost = _computePrice(len, cadence, duration);
      if (cadence == PaymentCadence.Annual) {
        newExpiry = currentExpiry + uint64(uint256(duration) * 365 days);
      } else {
        newExpiry = currentExpiry + uint64(uint256(duration) * 30 days);
      }
    }

    if (cost > 0) {
      USDC.safeTransferFrom(msg.sender, beneficiary, cost);
    }

    nameInfoOf[node].expiry = newExpiry;

    emit NameRenewed(node, label, newExpiry, cost);
  }

  /// @notice Register a subname under an existing DeFi ID.
  /// @dev The parent owner must first approve the registrar for their specific name
  ///      via `wrapper.approve(address(registrar), uint256(parentLabelNode))`.
  ///
  ///      The parent retains full ENS-level control of their children: since `_issue`
  ///      does not burn any fuses, the parent can re-call `registerSubname` (or use the
  ///      wrapper directly) to reassign an active child subname to a new owner at any
  ///      time. This function intentionally skips the availability check that `_issue`
  ///      applies to top-level labels.
  /// @param parentLabel The parent label (e.g. "alice" for alice.defi.com).
  /// @param childLabel  The child label to register (e.g. "sub" for sub.alice.defi.com).
  /// @param owner       The address that will own the subname (must not be zero).
  function registerSubname(
    string calldata parentLabel,
    string calldata childLabel,
    address owner
  ) external nonReentrant {
    _requireNotPaused();
    require(owner != address(0), ZeroAddress());
    LabelValidator.validateLabel(childLabel);

    bytes32 parentLabelNode = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes(parentLabel))));

    // Verify caller is parent owner or approved operator
    require(WRAPPER.canModifyName(parentLabelNode, msg.sender), NotOwner());
    // Verify registrar is approved to act on the parent node
    require(WRAPPER.canModifyName(parentLabelNode, address(this)), RegistrarNotApproved());
    // Prevent subnames under expired parents (read registrar-authoritative expiry; the wrapper's
    // value is unreliable when the top-level parent has a pathological expiry).
    uint64 parentExpiry = nameInfoOf[parentLabelNode].expiry;
    require(parentExpiry > block.timestamp, ParentExpired());

    bytes32 childNode =
      WRAPPER.setSubnodeRecord(parentLabelNode, childLabel, owner, defaultResolver, 0, 0, parentExpiry);
    nameInfoOf[childNode] = NameInfo({issuee: owner, expiry: parentExpiry});

    emit SubnameCreated(parentLabelNode, childLabel, childNode, owner);
  }

  /// @notice Check whether a label conforms to DeFi ID naming rules.
  function isValidLabel(
    string calldata label
  ) external pure returns (bool) {
    return LabelValidator.isValid(label);
  }

  /// @notice Compute the USDC cost for registering a label.
  /// @dev Reverts if the label is invalid or the duration is out of range.
  function getPrice(
    string calldata label,
    PaymentCadence cadence,
    uint8 duration
  ) external view returns (uint256) {
    LabelValidator.validateLabel(label);
    return _computePrice(bytes(label).length, cadence, duration);
  }

  function version() external pure returns (string memory) {
    return VERSION;
  }
}
