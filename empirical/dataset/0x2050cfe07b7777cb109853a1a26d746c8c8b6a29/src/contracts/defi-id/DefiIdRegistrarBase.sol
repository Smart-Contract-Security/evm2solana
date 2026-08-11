//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Ownable} from '@solady/auth/Ownable.sol';
import {ReentrancyGuard} from '@solady/utils/ReentrancyGuard.sol';
import {IDefiIdRegistrar} from 'interfaces/IDefiIdRegistrar.sol';
import {INameWrapper} from 'interfaces/INameWrapper.sol';

/// @title DefiIdRegistrarBase
/// @notice Abstract base for the DeFi ID registrar — storage, constructor, and shared internals.
abstract contract DefiIdRegistrarBase is Ownable, ReentrancyGuard, IDefiIdRegistrar {
  using SafeERC20 for IERC20;

  // ---- Constants ----

  uint64 public constant GRACE_PERIOD = 90 days;

  // ---- Immutables ----

  IERC20 public immutable USDC;
  bytes32 public immutable PARENT_NODE;
  INameWrapper public immutable WRAPPER;

  // ---- Mutable state ----

  address public beneficiary;
  address public defaultResolver;
  bool public paused;

  mapping(address => bytes32) public defiIdOf;

  /// @notice Per-node record written at `_issue` and cleared at `emergencyRevoke`.
  ///         `issuee` is the address the registrar originally minted this node to — the
  ///         authoritative source for revocation bookkeeping. NameWrapper ownership may
  ///         diverge from `issuee` after a user-initiated ERC-1155 transfer; that is
  ///         accepted and the registrar does not consult the wrapper for identity questions.
  ///         `expiry` is the registrar-authoritative expiry, decoupled from the wrapper (the
  ///         wrapper clamps child expiry to the parent's, which breaks when the parent is
  ///         DNS-imported with `expiry = 0`). All registrar invariants — availability,
  ///         uniqueness, renew, subname parent check — read `expiry` from here.
  struct NameInfo {
    address issuee;
    uint64 expiry;
  }

  mapping(bytes32 => NameInfo) public nameInfoOf;

  bytes32 public excludedRoot;

  /// @notice Base MONTHLY USDC price (6 decimals) for 3-character premium labels.
  /// @dev Monthly cadence charges `price3 * duration`. Annual cadence charges
  ///      `price3 * 12 * duration * 9 / 10` — a 10% discount for prepaying a year.
  uint256 public price3;
  /// @notice Base MONTHLY USDC price (6 decimals) for 4–5 character premium labels. See `price3`.
  uint256 public price45;
  /// @notice Base MONTHLY USDC price (6 decimals) for 6–7 character premium labels. See `price3`.
  uint256 public price67;

  /// @dev DEF-829 Path 1 scaffolding. Removed in V3.
  string[] internal _issuedLabels;

  // ---- Constructor ----

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
  ) {
    require(_wrapper != address(0), ZeroAddress());
    require(_usdc != address(0), ZeroAddress());
    require(_parentNode != bytes32(0), ZeroNode());
    require(_owner != address(0), ZeroAddress());
    require(_beneficiary != address(0), ZeroAddress());
    require(_defaultResolver != address(0), ZeroAddress());
    require(_price3 != 0, ZeroPrice());
    require(_price45 != 0, ZeroPrice());
    require(_price67 != 0, ZeroPrice());

    _initializeOwner(_owner);

    USDC = IERC20(_usdc);
    PARENT_NODE = _parentNode;
    WRAPPER = INameWrapper(_wrapper);
    beneficiary = _beneficiary;
    defaultResolver = _defaultResolver;
    price3 = _price3;
    price45 = _price45;
    price67 = _price67;
    excludedRoot = _excludedRoot;
  }

  // ---- Views ----

  /// @notice Whether `addr` has been issued a DeFi ID that the registrar still tracks as theirs.
  /// @dev True iff the registrar minted a name to `addr` and has not since cleared the pointer
  ///      via expiry re-registration, `adminIssue` re-point, or `emergencyRevoke`. Does not
  ///      reflect current NameWrapper holdership — if `addr` transferred the ERC-1155 away, this
  ///      still returns true until the pointer is cleared.
  function hasDefiId(
    address addr
  ) external view returns (bool) {
    return defiIdOf[addr] != bytes32(0);
  }

  function expiryOf(
    bytes32 node
  ) external view returns (uint64) {
    return nameInfoOf[node].expiry;
  }

  // ---- Internal helpers ----

  function _requireNotPaused() internal view {
    require(!paused, RegistrationPaused());
  }

  /// @dev Compute the USDC cost for a label based on its length, cadence, and duration.
  ///      Prices are quoted monthly; annual cadence applies a 10% discount for
  ///      prepaying twelve months per year. Returns 0 for standard labels (8+ chars).
  function _computePrice(
    uint256 labelLength,
    PaymentCadence cadence,
    uint8 duration
  ) internal view returns (uint256) {
    // Labels of 8+ characters are free; shorter premium labels (3-7 chars) are paid.
    // Callers validate `label` via `LabelValidator` before reaching here, so `labelLength`
    // is guaranteed to be in [3, 12]; no defensive length check is needed.
    if (labelLength >= 8) return 0;

    uint256 monthly;
    if (labelLength == 3) {
      monthly = price3;
    } else if (labelLength <= 5) {
      monthly = price45;
    } else {
      monthly = price67;
    }

    if (cadence == PaymentCadence.Annual) {
      // Annual: 1–5 years, 12 months/year at a 10% prepay discount.
      require(duration >= 1 && duration <= 5, InvalidDuration());
      return (monthly * 12 * duration * 9) / 10;
    } else {
      // Monthly: 1–60 months, pay the monthly rate per month.
      require(duration >= 1 && duration <= 60, InvalidDuration());
      return monthly * duration;
    }
  }

  /// @dev Compute pricing, expiry, and handle class for a label registration or whitelist claim.
  function _computeCostAndExpiry(
    uint256 len,
    PaymentCadence cadence,
    uint8 duration
  ) internal view returns (uint256 cost, uint64 expiry, HandleClass handleClass) {
    if (len >= 8) {
      cost = 0;
      expiry = uint64(block.timestamp + 365 days);
      handleClass = HandleClass.Standard;
    } else {
      cost = _computePrice(len, cadence, duration);
      handleClass = HandleClass.Premium;
      // Annual grants 365 days/yr while Monthly grants 30 days/mo, so an annual
      // prepay effectively saves ~11.2%/day vs. "10% off" — by design.
      if (cadence == PaymentCadence.Annual) {
        expiry = uint64(block.timestamp + uint256(duration) * 365 days);
      } else {
        expiry = uint64(block.timestamp + uint256(duration) * 30 days);
      }
    }
  }

  /// @dev Mint a new DeFi ID via the NameWrapper and update internal bookkeeping.
  ///      Caller must enforce all preconditions (paused, SMT checks, payment).
  function _issue(
    string calldata label,
    address owner,
    uint64 expiry,
    uint256 cost,
    HandleClass handleClass
  ) internal {
    require(owner != address(0), ZeroAddress());

    // Derive the ENS node for this label under our parent domain (namehash).
    bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes(label))));

    // Availability and identity are decided by `nameInfoOf` alone — the registrar is a
    // NameWrapper operator, not a custodian, so `wrapper.getData` is not consulted for
    // bookkeeping. `nameInfoOf[node].expiry == 0` means either "never issued" (fresh) or
    // "revoked by admin" (emergencyRevoke clears it). Both are available.
    NameInfo memory existing = nameInfoOf[node];
    require(existing.expiry == 0 || existing.expiry + GRACE_PERIOD < block.timestamp, LabelUnavailable());

    // Clear stale defiIdOf for the previous issuee of this label so they are not permanently
    // locked out of registering a new name. Uses our own `issuee` record rather than the
    // wrapper's current owner, so transfers of the ERC-1155 do not confuse this cleanup.
    if (existing.issuee != address(0) && existing.issuee != owner && defiIdOf[existing.issuee] == node) {
      defiIdOf[existing.issuee] = bytes32(0);
    }

    // If the owner already holds a DeFi ID, only allow re-registration once the previous
    // name has fully expired (including its grace period). `emergencyRevoke` clears
    // `nameInfoOf` for the revoked node, so a revoked user is unblocked immediately.
    bytes32 oldNode = defiIdOf[owner];
    if (oldNode != bytes32(0)) {
      uint64 oldExpiry = nameInfoOf[oldNode].expiry;
      require(oldExpiry == 0 || oldExpiry + GRACE_PERIOD < block.timestamp, AlreadyHasDefiId());
    }

    require(expiry > block.timestamp, InvalidExpiry());

    WRAPPER.setSubnodeRecord(PARENT_NODE, label, owner, defaultResolver, 0, 0, expiry);

    _issuedLabels.push(label);

    defiIdOf[owner] = node;
    nameInfoOf[node] = NameInfo({issuee: owner, expiry: expiry});

    emit NameRegistered(node, label, owner, expiry, cost, uint8(handleClass));
  }

  // ---- DEF-829: tracker accessors. Removed in V3. ----

  function issuedLabelsLength() external view returns (uint256) {
    return _issuedLabels.length;
  }

  function issuedLabelAt(
    uint256 i
  ) external view returns (string memory) {
    return _issuedLabels[i];
  }
}
