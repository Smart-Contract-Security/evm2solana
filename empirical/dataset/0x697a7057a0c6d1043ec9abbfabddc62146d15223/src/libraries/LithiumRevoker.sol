// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    Storage,
    SignedRevocation,
    Revocation,
    AssetVariant,
    AssetDistribution,
    Dispute,
    NotInDispute,
    InvalidAssetState,
    InvalidNonce,
    CLOSED_CHANNEL_SENTINEL
} from "../interfaces/ILithium.sol";
import {LithiumVerification} from "./LithiumVerification.sol";
import {LithiumTransfer} from "./LithiumTransfer.sol";

library LithiumRevoker {
    /// @notice Penalize a participant that broadcasted a revoked channel state.
    /// @dev Two enforcement paths per revocation:
    ///      1. **Dispute path** (cumulative only, balanceSum == 0): The revoker opened a dispute via
    ///         unilateralSettleChannel. Checked via store.assetDisputes.
    ///      2. **Cooperative path** (nonce-specific only, balanceSum > 0): The revoker called
    ///         updateChannel to broadcast a deposit/withdrawal state. Checked via store.assetChannels
    ///         using the stored hash keccak256(nonce, balanceSum, revoker).
    ///      Cumulative revocations (balanceSum == 0) ONLY check the dispute path, because cooperative
    ///      updates create legitimate residuals at lower nonces that must not be penalizable.
    ///      Nonce-specific revocations (balanceSum > 0) ONLY check the cooperative path, because
    ///      allowing them on the dispute path would enable a front-running attack where a counterparty
    ///      broadcasts updateChannel (changing balanceSum) and then penalizes the victim who must
    ///      dispute with the only state matching the new stored hash.
    ///      The function is permissionless: any caller can invoke it, but all funds go to the victim
    ///      (non-revoking party). The victim is determined by ECDSA signature recovery on the
    ///      revocation, making the reward recipient deterministic and front-running unprofitable.
    /// @param store The global storage struct.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param signedRevocations Array of revocation details with revoker's signature (one per asset).
    /// @return distributions Array of asset distributions (amounts and recipients per asset).
    function penalizeRevokedChannel(
        Storage storage store,
        address alice,
        address bob,
        uint256 channelNumber,
        SignedRevocation[] memory signedRevocations
    ) internal returns (AssetDistribution[] memory distributions) {
        uint256 length = signedRevocations.length;
        distributions = new AssetDistribution[](length);
        for (uint256 i = 0; i < length;) {
            SignedRevocation memory signedRevocation = signedRevocations[i];

            address revoker = LithiumVerification.verifyRevocationSignature(alice, bob, channelNumber, signedRevocation);

            Revocation memory revocation = signedRevocation.revocation;
            distributions[i] = _revokeAssetChannel(
                store,
                alice,
                bob,
                channelNumber,
                revocation.assetVariant,
                revocation.assetAddress,
                revocation.tokenNumberId,
                revocation.nonce,
                revocation.balanceSum,
                revoker
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Penalize using calldata for gas efficiency.
    /// @dev Calldata variant; identical logic to memory version.
    /// @param store The global storage struct.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param signedRevocations Array of revocation details with revoker's signature (one per asset).
    /// @return distributions Array of asset distributions (amounts and recipients per asset).
    function penalizeRevokedChannelCalldata(
        Storage storage store,
        address alice,
        address bob,
        uint256 channelNumber,
        SignedRevocation[] calldata signedRevocations
    ) internal returns (AssetDistribution[] memory distributions) {
        uint256 length = signedRevocations.length;
        distributions = new AssetDistribution[](length);
        for (uint256 i = 0; i < length;) {
            SignedRevocation calldata signedRevocation = signedRevocations[i];

            address revoker =
                LithiumVerification.verifyRevocationSignatureCalldata(alice, bob, channelNumber, signedRevocation);

            Revocation calldata revocation = signedRevocation.revocation;
            distributions[i] = _revokeAssetChannel(
                store,
                alice,
                bob,
                channelNumber,
                revocation.assetVariant,
                revocation.assetAddress,
                revocation.tokenNumberId,
                revocation.nonce,
                revocation.balanceSum,
                revoker
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Revoke an individual asset channel via the dispute path or the cooperative path.
    /// @dev The revocation mode is derived from `balanceSum`:
    ///      - `balanceSum == 0` → **cumulative** (dispute-path only)
    ///      - `balanceSum > 0`  → **nonce-specific** (cooperative-path only)
    ///      Two enforcement paths:
    ///      1. **Dispute path** (active dispute exists, cumulative only):
    ///         - The disputer must be the revoker.
    ///         - Nonce check: dispute.nonce <= revocation.nonce
    ///         - Total amount = dispute.balances.alice + dispute.balances.bob
    ///         - Nonce-specific revocations are NOT allowed on the dispute path. This prevents
    ///           a counterparty from front-running with updateChannel (changing balanceSum on-chain)
    ///           and then penalizing the victim who is forced to dispute with the only matching state.
    ///      2. **Cooperative path** (no active dispute, nonce-specific only):
    ///         - Verifies stored assetChannel hash matches keccak256(nonce, balanceSum, revoker)
    ///         - The revoker is the lastUpdater who called updateChannel
    ///         - Total amount = revocation.balanceSum
    ///      Cumulative revocations CANNOT use the cooperative path, because cooperative updates
    ///      create legitimate residuals at lower nonces (e.g., deposits before off-chain payments).
    ///      The conflation of `balanceSum == 0` with cumulative is safe: a nonce-specific revocation
    ///      with zero balance is vacuous (no funds to penalize), so widening the nonce check to `<=`
    ///      has no economic impact.
    ///      All funds are assigned to the victim (non-revoker), either via direct payout when the
    ///      victim is the caller or via `claimable` escrow otherwise. Clears both storage slots.
    /// @param store The global storage struct.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param assetVariant The asset type.
    /// @param assetAddress The asset contract address.
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    /// @param nonce The revoked nonce.
    /// @param balanceSum Total balance at the revoked nonce. 0 = cumulative, > 0 = nonce-specific.
    /// @param revoker The recovered signer of the revocation (Alice or Bob).
    /// @return assetDistribution The distribution details (amounts, recipients).
    function _revokeAssetChannel(
        Storage storage store,
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        uint256 nonce,
        uint256 balanceSum,
        address revoker
    ) private returns (AssetDistribution memory assetDistribution) {
        bytes32 assetChannelId = keccak256(
            abi.encodePacked(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId)
        );

        bool cumulative = balanceSum == 0;
        uint256 totalAmount = 0;
        {
            // Use storage pointer — avoids copying the entire Dispute struct (including the
            // dynamic HashlockPayment[] array) to memory. Only the fields actually accessed
            // are SLOADed, saving 3+ base SLOADs and 5N payment SLOADs.
            Dispute storage dispute = store.assetDisputes[assetChannelId];

            if (dispute.disputeDeadline > 0) {
                // ── Dispute path (cumulative only) ──
                // Only cumulative revocations (balanceSum == 0) are valid on the dispute path.
                // Nonce-specific revocations are restricted to the cooperative path to prevent
                // penalization when a counterparty front-runs with updateChannel (changing the
                // stored balanceSum), forcing the victim to dispute with the only matching state.
                if (!cumulative) revert InvalidAssetState();

                // The disputer must be the revoker (the party who broadcasted the revoked state)
                if (dispute.disputerIsAlice != (revoker == alice)) revert InvalidAssetState();

                // Cumulative nonce check: dispute.nonce must be ≤ revocation.nonce
                if (dispute.nonce > nonce) revert InvalidNonce();

                totalAmount = dispute.balances.alice + dispute.balances.bob;
            } else if (!cumulative) {
                // ── Cooperative path (nonce-specific only, balanceSum > 0) ──
                // The revoker called updateChannel, stored hash = keccak256(nonce, balanceSum, msg.sender)
                // We verify the revoker was the lastUpdater by matching the stored hash.
                bytes32 storedHash = store.assetChannels[assetChannelId];
                bytes32 expectedHash = keccak256(abi.encodePacked(nonce, balanceSum, revoker));
                if (storedHash != expectedHash) revert InvalidAssetState();

                totalAmount = balanceSum;
            } else {
                // Cumulative (balanceSum == 0) with no dispute — can't penalize
                revert NotInDispute();
            }
        }

        // All funds go to the victim (non-revoker)
        address victim = (revoker == alice) ? bob : alice;

        // Clear storage before transfers (CEI pattern)
        // Sentinel prevents signature replay across channel incarnations
        store.assetChannels[assetChannelId] = CLOSED_CHANNEL_SENTINEL;
        delete store.assetDisputes[assetChannelId];

        // Distribute deterministically: direct only if the victim is the caller.
        if (totalAmount > 0) {
            if (msg.sender == victim) {
                LithiumTransfer.withdrawAssetTo(victim, assetVariant, assetAddress, tokenNumberId, totalAmount);
            } else {
                store.claimable[
                        victim
                    ][keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId))] += totalAmount;
            }
        }

        assetDistribution = AssetDistribution({
            assetVariant: assetVariant,
            assetAddress: assetAddress,
            tokenNumberId: tokenNumberId,
            aliceAmount: (revoker == alice) ? 0 : totalAmount,
            bobAmount: (revoker == bob) ? 0 : totalAmount,
            aliceRecipient: alice,
            bobRecipient: bob
        });
    }
}
