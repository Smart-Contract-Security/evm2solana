// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {
    ChannelConfig,
    SignedAssetState,
    AssetState,
    AssetVariant,
    WithdrawSetting,
    SignedRevocation,
    Revocation,
    HashlockPayment,
    InvalidAliceSignature,
    InvalidBobSignature,
    InvalidPreimage,
    PaymentDeadlinePassed,
    InvalidRevokerSignature
} from "../interfaces/ILithium.sol";

library LithiumVerification {
    using MessageHashUtils for bytes;

    /// @notice Verify signatures for an asset channel state using memory parameters.
    /// @dev Constructs a message from channel config and asset state, prefixes it with Ethereum signed message hash,
    ///      and recovers signers using ECDSA.
    ///      Ensures no malleability issues by relying on OZ's ECDSA (best practice).
    /// @param channelConfig The channel configuration.
    /// @param signedAssetState The asset state with signatures.
    function verifyAssetChannelStateSignatures(
        ChannelConfig memory channelConfig,
        SignedAssetState memory signedAssetState
    ) internal view {
        address alice = channelConfig.alice;
        address bob = channelConfig.bob;
        AssetState memory assetState = signedAssetState.assetState;

        bytes32 ethSignedHash = _createAssetChannelStateSignableMessage(
            alice,
            bob,
            channelConfig.channelNumber,
            channelConfig.disputePeriod,
            assetState.withdrawSetting,
            assetState.assetVariant,
            assetState.assetAddress,
            assetState.tokenNumberId,
            assetState.nonce,
            assetState.onchainNonce,
            assetState.balances.alice,
            assetState.balances.bob,
            assetState.previousBalances.alice,
            assetState.previousBalances.bob,
            assetState.hashlockPaymentsMerkleRoot
        );

        if (ECDSA.recover(ethSignedHash, signedAssetState.aliceSignature) != alice) {
            revert InvalidAliceSignature();
        }
        if (ECDSA.recover(ethSignedHash, signedAssetState.bobSignature) != bob) {
            revert InvalidBobSignature();
        }
    }

    /// @notice Verify signatures for an asset channel state using calldata parameters.
    /// @dev Calldata version for gas efficiency in external calls. Similar to memory version but uses calldata for signatures.
    /// @param channelConfig The channel configuration.
    /// @param signedAssetState The asset state with signatures.
    function verifyAssetChannelStateSignaturesCalldata(
        ChannelConfig calldata channelConfig,
        SignedAssetState calldata signedAssetState
    ) internal view {
        address alice = channelConfig.alice;
        address bob = channelConfig.bob;
        AssetState calldata assetState = signedAssetState.assetState;

        bytes32 ethSignedHash = _createAssetChannelStateSignableMessage(
            alice,
            bob,
            channelConfig.channelNumber,
            channelConfig.disputePeriod,
            assetState.withdrawSetting,
            assetState.assetVariant,
            assetState.assetAddress,
            assetState.tokenNumberId,
            assetState.nonce,
            assetState.onchainNonce,
            assetState.balances.alice,
            assetState.balances.bob,
            assetState.previousBalances.alice,
            assetState.previousBalances.bob,
            assetState.hashlockPaymentsMerkleRoot
        );

        if (ECDSA.recover(ethSignedHash, signedAssetState.aliceSignature) != alice) {
            revert InvalidAliceSignature();
        }
        if (ECDSA.recover(ethSignedHash, signedAssetState.bobSignature) != bob) {
            revert InvalidBobSignature();
        }
    }

    /// @dev Constructs the EIP-191 Ethereum signed message hash for an asset channel state.
    ///      Includes address(this) and block.chainid to prevent cross-contract and cross-chain replay.
    ///      All fields are fixed-size types (address=20B, uint64=8B, uint256=32B, enum=1B, bytes32=32B). With
    ///      no dynamic-length types, `abi.encodePacked` produces an unambiguous encoding — no two
    ///      distinct input tuples produce the same byte sequence. Combined with domain separation
    ///      (address(this), chainid) and monotonic counters (nonce, onchainNonce), there is no
    ///      practical collision or replay risk. EIP-712 would add gas overhead without measurable
    ///      security benefit for this fixed-layout scheme.
    function _createAssetChannelStateSignableMessage(
        address alice,
        address bob,
        uint256 channelNumber,
        uint64 disputePeriod,
        WithdrawSetting withdrawSetting,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        uint256 nonce,
        uint256 onchainNonce,
        uint256 aliceBalance,
        uint256 bobBalance,
        uint256 prevAliceBalance,
        uint256 prevBobBalance,
        bytes32 hashlockPaymentsMerkleRoot
    ) private view returns (bytes32) {
        return abi.encodePacked(
                address(this),
                block.chainid,
                alice,
                bob,
                channelNumber,
                disputePeriod,
                withdrawSetting,
                assetVariant,
                assetAddress,
                tokenNumberId,
                nonce,
                onchainNonce,
                aliceBalance,
                bobBalance,
                prevAliceBalance,
                prevBobBalance,
                hashlockPaymentsMerkleRoot
            ).toEthSignedMessageHash();
    }

    /// @notice Verify the revoker's signature for a revocation using memory parameters.
    /// @dev Constructs a message from revocation details, recovers the signer via ECDSA.
    ///      The signer must be either Alice or Bob. Returns the recovered revoker address.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param signedRevocation The revocation details with the revoker's signature.
    /// @return revoker The address that signed the revocation (Alice or Bob).
    function verifyRevocationSignature(
        address alice,
        address bob,
        uint256 channelNumber,
        SignedRevocation memory signedRevocation
    ) internal view returns (address revoker) {
        Revocation memory revocation = signedRevocation.revocation;
        bytes32 ethSignedHash = _createRevocationSignableMessage(
            alice,
            bob,
            channelNumber,
            revocation.assetVariant,
            revocation.assetAddress,
            revocation.tokenNumberId,
            revocation.nonce,
            revocation.balanceSum
        );

        revoker = ECDSA.recover(ethSignedHash, signedRevocation.revokerSignature);
        if (revoker != alice && revoker != bob) {
            revert InvalidRevokerSignature();
        }
    }

    /// @notice Verify the revoker's signature for a revocation using calldata parameters.
    /// @dev Calldata version for gas efficiency in external calls.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param signedRevocation The revocation details with the revoker's signature.
    /// @return revoker The address that signed the revocation (Alice or Bob).
    function verifyRevocationSignatureCalldata(
        address alice,
        address bob,
        uint256 channelNumber,
        SignedRevocation calldata signedRevocation
    ) internal view returns (address revoker) {
        Revocation calldata revocation = signedRevocation.revocation;
        bytes32 ethSignedHash = _createRevocationSignableMessage(
            alice,
            bob,
            channelNumber,
            revocation.assetVariant,
            revocation.assetAddress,
            revocation.tokenNumberId,
            revocation.nonce,
            revocation.balanceSum
        );

        revoker = ECDSA.recover(ethSignedHash, signedRevocation.revokerSignature);
        if (revoker != alice && revoker != bob) {
            revert InvalidRevokerSignature();
        }
    }

    /// @dev Constructs the EIP-191 Ethereum signed message hash for a revocation.
    ///      Includes address(this) and block.chainid to prevent cross-contract and cross-chain replay.
    ///      Includes balanceSum to bind the revocation to a specific balance total.
    ///      balanceSum doubles as the cumulative/nonce-specific discriminant (0 = cumulative, >0 = nonce-specific).
    ///      All fields are fixed-size types; see `_createAssetChannelStateSignableMessage` for
    ///      full encoding safety rationale.
    function _createRevocationSignableMessage(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        uint256 nonce,
        uint256 balanceSum
    ) private view returns (bytes32) {
        return abi.encodePacked(
                address(this),
                block.chainid,
                alice,
                bob,
                channelNumber,
                assetVariant,
                assetAddress,
                tokenNumberId,
                nonce,
                balanceSum
            ).toEthSignedMessageHash();
    }

    /// @notice Calculate Merkle root and verify preimages for hashlock payments using memory array.
    /// @dev Builds a binary Merkle tree using keccak256, verifies provided preimages with sha256,
    ///      and checks resolution deadlines. Leaves are hashed without sorting (assumes consistent order).
    ///      Returns 0 for empty array. Gas-efficient for small arrays; the off-chain node should
    ///      cap HTLC count to 50–100 per asset per state to bound gas and calldata overhead.
    /// @param hashlockPayments Array of payments to process.
    /// @return The computed Merkle root (bytes32(0) if empty).
    function calculateMerkleRootAndVerifyPreimages(HashlockPayment[] memory hashlockPayments)
        internal
        view
        returns (bytes32)
    {
        uint256 length = hashlockPayments.length;
        if (length == 0) return bytes32(0);

        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            HashlockPayment memory payment = hashlockPayments[i];
            if (payment.preimage != bytes32(0)) {
                if (sha256(abi.encodePacked(payment.preimage)) != payment.hash) revert InvalidPreimage();
                if (block.timestamp > payment.resolutionDeadline) revert PaymentDeadlinePassed();
            }
            hashes[i] = keccak256(
                abi.encodePacked(payment.amount, payment.hash, payment.resolutionDeadline, payment.direction)
            );
            unchecked {
                ++i;
            }
        }

        // Build Merkle tree level by level
        return _buildMerkleTree(hashes, length);
    }

    /// @notice Calculate Merkle root and verify preimages for hashlock payments using calldata array.
    /// @dev Calldata version for gas efficiency. Identical logic to memory version.
    /// @param hashlockPayments Array of payments to process.
    /// @return The computed Merkle root (bytes32(0) if empty).
    function calculateMerkleRootAndVerifyPreimagesCalldata(HashlockPayment[] calldata hashlockPayments)
        internal
        view
        returns (bytes32)
    {
        uint256 length = hashlockPayments.length;
        if (length == 0) return bytes32(0);

        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            HashlockPayment calldata payment = hashlockPayments[i];
            if (payment.preimage != bytes32(0)) {
                if (sha256(abi.encodePacked(payment.preimage)) != payment.hash) revert InvalidPreimage();
                if (block.timestamp > payment.resolutionDeadline) revert PaymentDeadlinePassed();
            }
            hashes[i] = keccak256(
                abi.encodePacked(payment.amount, payment.hash, payment.resolutionDeadline, payment.direction)
            );
            unchecked {
                ++i;
            }
        }

        // Build Merkle tree level by level
        return _buildMerkleTree(hashes, length);
    }

    /// @dev Builds binary Merkle tree level-by-level from leaf hashes. Odd-length levels promote
    ///      the last element unpaired. No leaf sorting (assumes consistent order from caller).
    /// @param leaves Array of leaf hashes (modified in-place during tree construction).
    /// @param length Number of leaves.
    /// @return root The computed Merkle root.
    function _buildMerkleTree(bytes32[] memory leaves, uint256 length) private pure returns (bytes32) {
        // Build Merkle tree level by level
        while (length > 1) {
            uint256 j = 0;
            uint256 half = length / 2;
            for (uint256 i = 0; i < half;) {
                leaves[j] = keccak256(abi.encodePacked(leaves[2 * i], leaves[2 * i + 1]));
                unchecked {
                    ++i;
                    ++j;
                }
            }
            if (length & 1 != 0) {
                leaves[j] = leaves[length - 1];
                unchecked {
                    ++j;
                }
            }
            length = j;
        }
        return leaves[0];
    }
}
