//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ECDSA} from '@solady/utils/ECDSA.sol';
import {EIP712} from '@solady/utils/EIP712.sol';
import {MerkleProofLib} from '@solady/utils/MerkleProofLib.sol';
import {SparseMerkleTree} from '@solarity-solidity-lib/libs/data-structures/SparseMerkleTree.sol';
import {DefiIdRegistrarAdmin} from 'contracts/defi-id/DefiIdRegistrarAdmin.sol';
import {LabelValidator} from 'contracts/libs/LabelValidator.sol';
import {SMTVerifier} from 'contracts/libs/SMTVerifier.sol';

/// @title DefiIdRegistrarWhitelist
/// @notice Whitelist claim logic for users who locked names via NameLocker.
///         The original address signs an EIP-712 message authorizing a new owner
///         to claim their pre-registered label.
abstract contract DefiIdRegistrarWhitelist is DefiIdRegistrarAdmin, EIP712 {
  using SafeERC20 for IERC20;

  // ---- Constants ----

  /// @notice Contract version — binds the EIP-712 domain separator and is exposed via
  ///         `DefiIdRegistrar.version()`. Bumping this invalidates prior whitelist signatures.
  string public constant VERSION = '2';

  /// @dev EIP-712 typehash for whitelist claims.
  bytes32 private constant _WHITELIST_CLAIM_TYPEHASH =
    keccak256('WhitelistClaim(address originalAddress,address newOwner,bytes32 labelHash)');

  // ---- State ----

  /// @notice Merkle root of the whitelist tree. bytes32(0) means whitelist is inactive.
  bytes32 public whitelistRoot;

  /// @notice Tracks which whitelist leaves have been claimed.
  mapping(bytes32 => bool) public whitelistClaimed;

  // ---- Admin ----

  /// @notice Update the whitelist Merkle root.
  /// @param root The new Merkle root (bytes32(0) disables whitelist claims).
  function setWhitelistRoot(
    bytes32 root
  ) external onlyOwner {
    whitelistRoot = root;
    emit WhitelistRootUpdated(root);
  }

  // ---- Whitelist claim ----

  /// @notice Claim a whitelisted name using a signature from the original address.
  /// @dev The original address must sign an EIP-712 message authorizing the claim
  ///      to the new owner. The (originalAddress, label) pair must exist in the
  ///      whitelist Merkle tree. Each leaf can only be claimed once.
  ///      Regular pricing applies: free for 8+ char labels, USDC for 3-7 char labels.
  /// @param label           The label to claim (e.g. "alice" for alice.defi.com).
  /// @param newOwner        The address that will own the wrapped name.
  /// @param originalAddress The address that locked this name and signed the authorization.
  /// @param signature       EIP-712 signature from originalAddress authorizing the claim.
  /// @param merkleProof     Merkle proof that (originalAddress, label) is in the whitelist tree.
  /// @param cadence         Payment cadence (Annual or Monthly). Ignored for standard labels.
  /// @param duration        Term length in years (Annual) or months (Monthly). Ignored for standard labels.
  function claimWhitelistName(
    string calldata label,
    address newOwner,
    address originalAddress,
    bytes calldata signature,
    bytes32[] calldata merkleProof,
    PaymentCadence cadence,
    uint8 duration,
    SparseMerkleTree.Proof calldata excludedProof
  ) external nonReentrant {
    _requireNotPaused();
    require(whitelistRoot != bytes32(0), WhitelistNotActive());

    LabelValidator.validateLabel(label);

    // SMT policy check — same as register(), skipped when the excluded root is unset.
    if (excludedRoot != bytes32(0)) {
      bytes32 leafKey = keccak256(abi.encodePacked(label));
      require(SMTVerifier.verifyNonInclusion(excludedProof, excludedRoot, leafKey), LabelExcluded());
    }

    bytes32 labelHash = keccak256(bytes(label));

    // Verify Merkle proof: (originalAddress, label) is in the whitelist.
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(originalAddress, labelHash))));
    require(MerkleProofLib.verifyCalldata(merkleProof, whitelistRoot, leaf), InvalidMerkleProof());

    // Prevent double-claiming.
    require(!whitelistClaimed[leaf], AlreadyClaimed());

    // Verify EIP-712 signature from originalAddress.
    bytes32 structHash = keccak256(abi.encode(_WHITELIST_CLAIM_TYPEHASH, originalAddress, newOwner, labelHash));
    bytes32 digest = _hashTypedData(structHash);
    require(ECDSA.recover(digest, signature) == originalAddress, InvalidSignature());

    whitelistClaimed[leaf] = true;

    (uint256 cost, uint64 expiry, HandleClass handleClass) =
      _computeCostAndExpiry(bytes(label).length, cadence, duration);

    if (cost > 0) {
      USDC.safeTransferFrom(msg.sender, beneficiary, cost);
    }

    _issue(label, newOwner, expiry, cost, handleClass);

    bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, labelHash));
    emit WhitelistNameClaimed(node, label, newOwner, originalAddress);
  }

  // ---- EIP-712 ----

  /// @dev Required by Solady EIP712. Provides the domain name and version for the EIP-712
  ///      domain separator, which binds signatures to this contract and chain.
  function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
    name = 'DefiIdRegistrar';
    version = VERSION;
  }
}
