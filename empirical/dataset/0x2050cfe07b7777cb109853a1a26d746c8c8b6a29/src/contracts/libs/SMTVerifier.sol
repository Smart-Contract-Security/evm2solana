//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SparseMerkleTree} from '@solarity-solidity-lib/libs/data-structures/SparseMerkleTree.sol';

/// @notice Stateless SMT proof verifier using Solarity's Proof struct.
/// @dev Attach to SparseMerkleTree.Proof via `using SMTVerifier for SparseMerkleTree.Proof`.
library SMTVerifier {
  /// @notice Recompute the SMT root from a proof.
  /// @dev Assumes the tree uses Solarity's default keccak256 hasher. Trees initialized with
  ///      a custom hasher will produce incorrect results.
  function processProof(
    SparseMerkleTree.Proof calldata proof
  ) internal pure returns (bytes32) {
    bytes32 computedHash;

    if (proof.existence) {
      computedHash = keccak256(abi.encodePacked(proof.key, proof.value, bytes32(uint256(1))));
    } else if (proof.auxExistence) {
      computedHash = keccak256(abi.encodePacked(proof.auxKey, proof.auxValue, bytes32(uint256(1))));
    }

    uint256 pathIndex = uint256(proof.key);
    uint256 depth = proof.siblings.length;

    // Trim trailing zero siblings. Safe because in a Solarity SMT the deepest meaningful
    // sibling is always non-zero — empty subtrees only appear as intermediate siblings,
    // never at the leaf-adjacent level (tree compaction guarantees this).
    while (depth > 0 && proof.siblings[depth - 1] == bytes32(0)) {
      unchecked {
        --depth;
      }
    }

    for (uint256 i = depth; i > 0; i--) {
      uint256 sIndex = i - 1;
      if ((pathIndex >> sIndex) & 1 == 1) {
        computedHash = keccak256(abi.encodePacked(proof.siblings[sIndex], computedHash));
      } else {
        computedHash = keccak256(abi.encodePacked(computedHash, proof.siblings[sIndex]));
      }
    }

    return computedHash;
  }

  /// @notice Verify a non-inclusion proof for a given key and expected root.
  function verifyNonInclusion(
    SparseMerkleTree.Proof calldata proof,
    bytes32 expectedRoot,
    bytes32 leafKey
  ) internal pure returns (bool) {
    if (proof.existence) return false;
    if (expectedRoot == bytes32(0)) return false;
    if (proof.root != expectedRoot) return false;
    if (proof.key != leafKey) return false;
    if (proof.auxExistence && proof.key == proof.auxKey) return false;
    return processProof(proof) == proof.root;
  }
}
