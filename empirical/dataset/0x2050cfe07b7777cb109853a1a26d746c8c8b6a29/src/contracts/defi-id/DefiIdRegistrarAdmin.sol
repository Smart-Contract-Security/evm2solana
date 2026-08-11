//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {DefiIdRegistrarBase} from 'contracts/defi-id/DefiIdRegistrarBase.sol';
import {LabelValidator} from 'contracts/libs/LabelValidator.sol';

/// @title DefiIdRegistrarAdmin
/// @notice Owner-only administrative functions for the DeFi ID registrar.
abstract contract DefiIdRegistrarAdmin is DefiIdRegistrarBase {
  using SafeERC20 for IERC20;

  // ---- Admin issuance ----

  /// @notice Issue a label to an address with any handle class.
  /// @dev Skips the uniqueness check — admin may issue to addresses that already hold a name.
  /// @param label   The label to issue (e.g. "bitcoin").
  /// @param owner   The address that will own the wrapped name.
  /// @param handleClass The handle class for event emission and classification.
  /// @param expiry  Absolute expiry timestamp (must be in the future).
  function adminIssue(
    string calldata label,
    address owner,
    HandleClass handleClass,
    uint64 expiry
  ) external onlyOwner nonReentrant {
    LabelValidator.validateLabel(label);

    // Clear defiIdOf so _issue() skips the AlreadyHasDefiId check.
    // _issue() will set defiIdOf[owner] back to the newly-issued node.
    defiIdOf[owner] = bytes32(0);

    _issue(label, owner, expiry, 0, handleClass);
  }

  // ---- Policy management (SMT roots) ----

  /// @notice Update the excluded-labels SMT root.
  /// @param root The new Merkle root (bytes32(0) disables the check).
  function setExcludedRoot(
    bytes32 root
  ) external onlyOwner {
    excludedRoot = root;
    emit ExcludedRootUpdated(root);
  }

  // ---- Pause ----

  /// @notice Pause public registration and renewal.
  function pause() external onlyOwner {
    paused = true;
    emit Paused();
  }

  /// @notice Unpause public registration and renewal.
  function unpause() external onlyOwner {
    paused = false;
    emit Unpaused();
  }

  // ---- Operational setters ----

  /// @notice Set the USDC fee recipient address.
  /// @param _beneficiary The new beneficiary address (must not be zero).
  function setBeneficiary(
    address _beneficiary
  ) external onlyOwner {
    require(_beneficiary != address(0), ZeroAddress());
    beneficiary = _beneficiary;
    emit BeneficiaryUpdated(_beneficiary);
  }

  /// @notice Set the default ENS resolver for newly issued names.
  /// @param _resolver The new resolver address (must not be zero).
  function setDefaultResolver(
    address _resolver
  ) external onlyOwner {
    require(_resolver != address(0), ZeroAddress());
    defaultResolver = _resolver;
    emit DefaultResolverUpdated(_resolver);
  }

  /// @notice Update monthly USDC prices for premium labels by character-length tier.
  /// @dev Monthly cadence charges `price * duration`; annual cadence charges
  ///      `price * 12 * duration * 9 / 10` (a 10% discount applied per year of an annual prepay).
  /// @param _price3  Monthly price for 3-character labels (USDC, 6 decimals).
  /// @param _price45 Monthly price for 4–5 character labels (USDC, 6 decimals).
  /// @param _price67 Monthly price for 6–7 character labels (USDC, 6 decimals).
  function setPrices(
    uint256 _price3,
    uint256 _price45,
    uint256 _price67
  ) external onlyOwner {
    require(_price3 != 0, ZeroPrice());
    require(_price45 != 0, ZeroPrice());
    require(_price67 != 0, ZeroPrice());
    price3 = _price3;
    price45 = _price45;
    price67 = _price67;
    emit PricesUpdated(_price3, _price45, _price67);
  }

  // ---- Fund recovery ----

  /// @notice Recover stuck tokens or force-pushed ETH to a caller-specified recipient.
  /// @param token  The token address, or address(0) for native ETH.
  /// @param amount The amount to recover.
  /// @param to     The recipient address (must not be zero). Decoupled from `beneficiary`
  ///               so compromised/misconfigured revenue routing does not block recovery.
  function recoverFunds(
    address token,
    uint256 amount,
    address to
  ) external onlyOwner nonReentrant {
    require(to != address(0), ZeroAddress());
    if (token == address(0)) {
      (bool ok,) = to.call{value: amount}('');
      require(ok, TransferFailed());
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
    emit FundsRecovered(token, amount, to);
  }

  // ---- Emergency ----

  /// @notice Revoke a name by reassigning ownership to the registrar's owner (multisig).
  /// @dev Clears defiIdOf for the original issuee so they can re-register. The registrar
  ///      is a NameWrapper operator — it cannot and must not hold ENS tokens itself,
  ///      so the revocation sink is `owner()`. The issuee is read from `nameInfoOf`
  ///      (the registrar's own record), not from the wrapper, so transfers of the
  ///      ERC-1155 do not divert the clear away from the address that actually holds
  ///      the orphaned `defiIdOf` pointer.
  /// @param label The full label string (e.g. "alice").
  function emergencyRevoke(
    string calldata label
  ) external onlyOwner nonReentrant {
    bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes(label))));
    NameInfo memory current = nameInfoOf[node];

    // Nothing to revoke: label was never issued (or already fully cleared). Exit without
    // emitting NameRevoked so indexers don't log phantom revocations.
    if (current.issuee == address(0) && current.expiry == 0) {
      return;
    }

    if (current.issuee != address(0) && defiIdOf[current.issuee] == node) {
      defiIdOf[current.issuee] = bytes32(0);
    }

    // Clear the per-node record so the label is available and no stale issuee remains.
    delete nameInfoOf[node];

    // If the name has already expired past the grace period, setSubnodeRecord may fail
    // because the NameWrapper treats the child as no longer controlled by the parent.
    // In this case, revocation is unnecessary — the name is already available.
    if (current.expiry + GRACE_PERIOD >= block.timestamp) {
      WRAPPER.setSubnodeRecord(PARENT_NODE, label, owner(), defaultResolver, 0, 0, current.expiry);
    }

    emit NameRevoked(node, label);
  }

  // ---- DEF-829: bulk wipe for V3 cutover. Removed in V3. ----

  event NamesWiped(uint256 indexed start, uint256 count);

  /// @dev DEF-829 Path 1 scaffolding. REMOVE IN NEXT VERSION.
  ///      Sweeps the `_issuedLabels` tracker in the range `[start, start+count)` and:
  ///      - clears `defiIdOf` / `nameInfoOf` for each label
  ///      - calls the canonical NameWrapper burn (`owner=0, expiry=0`), which burns the
  ///        ERC-1155 and clears the ENS registry record — genuinely "as-if-never-registered".
  ///      Past-grace entries are burned too: NameWrapper's burn branch is expected to skip
  ///      the parent-expiry normalisation that the re-issuance branch performs.
  function adminWipeAll(uint256 start, uint256 count) external onlyOwner nonReentrant {
    uint256 len = _issuedLabels.length;
    if (start >= len) return;
    uint256 end = start + count;
    if (end > len) end = len;

    for (uint256 i = start; i < end; ++i) {
      string memory label = _issuedLabels[i];
      bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes(label))));
      NameInfo memory current = nameInfoOf[node];

      if (current.issuee != address(0) && defiIdOf[current.issuee] == node) {
        defiIdOf[current.issuee] = bytes32(0);
      }
      delete nameInfoOf[node];

      WRAPPER.setSubnodeRecord(PARENT_NODE, label, address(0), address(0), 0, 0, 0);
    }

    emit NamesWiped(start, end - start);
  }
}
