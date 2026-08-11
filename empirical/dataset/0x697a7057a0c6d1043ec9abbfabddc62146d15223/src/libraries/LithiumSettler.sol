// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    Storage,
    ChannelConfig,
    SignedAssetState,
    AssetState,
    AssetVariant,
    HashlockPayment,
    Dispute,
    AssetDistribution,
    PaymentDirection,
    LengthMismatch,
    InvalidNonce,
    InvalidMerkleRoot,
    InvalidAssetState,
    NoNewPayments,
    InvalidPaymentsLength,
    NoNewPreimages,
    NotInDispute,
    DisputePeriodNotPassed,
    InvalidPreviousState,
    InvalidSender,
    InvalidDisputePeriod,
    CLOSED_CHANNEL_SENTINEL
} from "../interfaces/ILithium.sol";
import {LithiumVerification} from "./LithiumVerification.sol";
import {LithiumTransfer} from "./LithiumTransfer.sol";

library LithiumSettler {
    /// @notice Unilaterally settle the channel by providing the latest states and signatures.
    ///         Pending hashlock payments require preimages; unknown preimages set to bytes32(0).
    ///         Initiates or updates a dispute for each asset.
    /// @dev Signatures are verified; previous state must match on-chain hash.
    ///      New nonces update full state; same nonce only allows new HTLC preimages.
    /// @param store The global storage struct.
    /// @param channelConfig The channel configuration.
    /// @param signedAssetStates Array of asset states with signatures.
    /// @param hashlockPaymentsArray Arrays of pending hashlock payments for each asset state.
    function unilateralSettleChannel(
        Storage storage store,
        ChannelConfig memory channelConfig,
        SignedAssetState[] memory signedAssetStates,
        HashlockPayment[][] memory hashlockPaymentsArray
    ) internal {
        uint256 length = signedAssetStates.length;
        if (hashlockPaymentsArray.length != length) revert LengthMismatch();

        for (uint256 i = 0; i < length;) {
            SignedAssetState memory signedAssetState = signedAssetStates[i];

            LithiumVerification.verifyAssetChannelStateSignatures(channelConfig, signedAssetState);

            AssetState memory assetState = signedAssetState.assetState;

            _unilateralSettleAssetChannel(store, channelConfig, assetState, hashlockPaymentsArray[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Unilaterally settle the channel using calldata for gas efficiency.
    /// @dev Calldata variant for external calls; identical logic to memory version.
    /// @param store The global storage struct.
    /// @param channelConfig The channel configuration.
    /// @param signedAssetStates Array of asset states with signatures.
    /// @param hashlockPaymentsArray Arrays of pending hashlock payments for each asset state.
    function unilateralSettleChannelCalldata(
        Storage storage store,
        ChannelConfig calldata channelConfig,
        SignedAssetState[] calldata signedAssetStates,
        HashlockPayment[][] calldata hashlockPaymentsArray
    ) internal {
        uint256 length = signedAssetStates.length;
        if (hashlockPaymentsArray.length != length) revert LengthMismatch();

        for (uint256 i = 0; i < length;) {
            SignedAssetState calldata signedAssetState = signedAssetStates[i];

            LithiumVerification.verifyAssetChannelStateSignaturesCalldata(channelConfig, signedAssetState);

            AssetState calldata assetState = signedAssetState.assetState;

            _unilateralSettleAssetChannelCalldata(store, channelConfig, assetState, hashlockPaymentsArray[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Unilaterally settle an individual asset channel.
    /// @dev Updates or initiates dispute; validates prev state and Merkle root.
    ///      For same nonce: Only new preimages allowed (no state changes).
    ///      Higher-nonce submissions override lower-nonce disputes without penalty;
    ///      fraud penalties are handled exclusively by the revocation mechanism.
    ///      After the initial dispute is opened by Alice or Bob, any caller can submit a
    ///      higher-nonce co-signed state to update the dispute. This enables watchtower-style
    ///      monitoring and recovery. Safety is guaranteed because every submitted state must
    ///      carry valid co-signatures from both parties.
    ///      If payments provided, recomputes and verifies Merkle root matches signed root.
    ///      If the signed root is non-zero, payments MUST be provided (no omission allowed).
    ///      When overriding with a higher nonce and no payments provided, stale hashlockPayments
    ///      from the previous dispute are deleted.
    ///      For ERC721, no on-chain validation of `aliceBalance + bobBalance <= 1` is performed.
    ///      Both parties must co-sign, so an invalid balance requires mutual agreement. The
    ///      transfer layer enforces `amount == 1` in `withdrawAssetTo`, catching invalids.
    ///      Off-chain: Set resolutionDeadlines with buffers for monitoring/responses.
    /// @param store The global storage struct.
    /// @param channelConfig The channel configuration.
    /// @param assetState The asset state.
    /// @param hashlockPayments Array of hashlock payments with preimages.
    function _unilateralSettleAssetChannel(
        Storage storage store,
        ChannelConfig memory channelConfig,
        AssetState memory assetState,
        HashlockPayment[] memory hashlockPayments
    ) internal {
        bytes32 assetChannelId = keccak256(
            abi.encodePacked(
                channelConfig.alice,
                channelConfig.bob,
                channelConfig.channelNumber,
                assetState.assetVariant,
                assetState.assetAddress,
                assetState.tokenNumberId
            )
        );
        Dispute storage dispute = store.assetDisputes[assetChannelId];

        if (dispute.disputeDeadline == 0 && msg.sender != channelConfig.alice && msg.sender != channelConfig.bob) {
            revert InvalidSender();
        }

        uint256 nonce = assetState.nonce;

        if (nonce < dispute.nonce || nonce <= assetState.onchainNonce) revert InvalidNonce();

        // Verify Merkle root: if payments provided, recompute; if root != 0 and no payments, revert
        uint256 paymentsLength = hashlockPayments.length;
        if (paymentsLength > 0) {
            bytes32 root = LithiumVerification.calculateMerkleRootAndVerifyPreimages(hashlockPayments);
            if (assetState.hashlockPaymentsMerkleRoot != root) revert InvalidMerkleRoot();
        } else if (assetState.hashlockPaymentsMerkleRoot != bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        if (dispute.disputeDeadline == 0 || nonce > dispute.nonce) {
            // New or higher nonce: Full state update
            bytes32 storedStateHash = store.assetChannels[assetChannelId];

            _validatePreviousStateAndUpdateDispute(
                dispute,
                storedStateHash,
                channelConfig.alice,
                channelConfig.bob,
                nonce,
                assetState.onchainNonce,
                assetState.balances.alice,
                assetState.balances.bob,
                assetState.hashlockPaymentsMerkleRoot,
                channelConfig.disputePeriod
            );

            // Copy payments (or clear stale payments from previous dispute)
            if (paymentsLength > 0) {
                dispute.hashlockPayments = new HashlockPayment[](paymentsLength);
                for (uint256 j = 0; j < paymentsLength;) {
                    dispute.hashlockPayments[j] = hashlockPayments[j];
                    unchecked {
                        ++j;
                    }
                }
            } else if (dispute.hashlockPayments.length > 0) {
                // Higher-nonce override with no payments: clear stale array from previous dispute
                delete dispute.hashlockPayments;
            }
        } else {
            // Same nonce: Validate state, allow only new preimages
            if (
                assetState.balances.alice != dispute.balances.alice || assetState.balances.bob != dispute.balances.bob
                    || assetState.hashlockPaymentsMerkleRoot != dispute.hashlockPaymentsMerkleRoot
            ) revert InvalidAssetState();

            uint256 disputePaymentsLength = dispute.hashlockPayments.length;
            if (disputePaymentsLength == 0) revert NoNewPayments();

            // Allow incremental preimage updates within fixed dispute period (no deadline extension).
            if (paymentsLength != disputePaymentsLength) revert InvalidPaymentsLength();

            bool newPreimageFound = false;
            for (uint256 j = 0; j < paymentsLength;) {
                if (dispute.hashlockPayments[j].preimage == bytes32(0) && hashlockPayments[j].preimage != bytes32(0)) {
                    newPreimageFound = true;
                    dispute.hashlockPayments[j].preimage = hashlockPayments[j].preimage;
                }
                unchecked {
                    ++j;
                }
            }
            if (!newPreimageFound) revert NoNewPreimages();
        }
    }

    /// @notice Unilaterally settle an individual asset channel using calldata.
    /// @dev Calldata variant; identical logic to memory version. See `_unilateralSettleAssetChannel`
    ///      for full documentation on permissionless post-initiation updates and ERC721 balances.
    /// @param store The global storage struct.
    /// @param channelConfig The channel configuration.
    /// @param assetState The asset state.
    /// @param hashlockPayments Array of hashlock payments with preimages.
    function _unilateralSettleAssetChannelCalldata(
        Storage storage store,
        ChannelConfig calldata channelConfig,
        AssetState calldata assetState,
        HashlockPayment[] calldata hashlockPayments
    ) internal {
        bytes32 assetChannelId = keccak256(
            abi.encodePacked(
                channelConfig.alice,
                channelConfig.bob,
                channelConfig.channelNumber,
                assetState.assetVariant,
                assetState.assetAddress,
                assetState.tokenNumberId
            )
        );
        Dispute storage dispute = store.assetDisputes[assetChannelId];

        if (dispute.disputeDeadline == 0 && msg.sender != channelConfig.alice && msg.sender != channelConfig.bob) {
            revert InvalidSender();
        }

        uint256 nonce = assetState.nonce;

        if (nonce < dispute.nonce || nonce <= assetState.onchainNonce) revert InvalidNonce();

        // Verify Merkle root: if payments provided, recompute; if root != 0 and no payments, revert
        uint256 paymentsLength = hashlockPayments.length;
        if (paymentsLength > 0) {
            bytes32 root = LithiumVerification.calculateMerkleRootAndVerifyPreimagesCalldata(hashlockPayments);
            if (assetState.hashlockPaymentsMerkleRoot != root) revert InvalidMerkleRoot();
        } else if (assetState.hashlockPaymentsMerkleRoot != bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        if (dispute.disputeDeadline == 0 || nonce > dispute.nonce) {
            // New or higher nonce: Full state update
            bytes32 storedStateHash = store.assetChannels[assetChannelId];

            _validatePreviousStateAndUpdateDispute(
                dispute,
                storedStateHash,
                channelConfig.alice,
                channelConfig.bob,
                nonce,
                assetState.onchainNonce,
                assetState.balances.alice,
                assetState.balances.bob,
                assetState.hashlockPaymentsMerkleRoot,
                channelConfig.disputePeriod
            );

            // Copy payments (or clear stale payments from previous dispute)
            if (paymentsLength > 0) {
                dispute.hashlockPayments = new HashlockPayment[](paymentsLength);
                for (uint256 j = 0; j < paymentsLength;) {
                    dispute.hashlockPayments[j] = hashlockPayments[j];
                    unchecked {
                        ++j;
                    }
                }
            } else if (dispute.hashlockPayments.length > 0) {
                // Higher-nonce override with no payments: clear stale array from previous dispute
                delete dispute.hashlockPayments;
            }
        } else {
            // Same nonce: Validate state, allow only new preimages
            if (
                assetState.balances.alice != dispute.balances.alice || assetState.balances.bob != dispute.balances.bob
                    || assetState.hashlockPaymentsMerkleRoot != dispute.hashlockPaymentsMerkleRoot
            ) revert InvalidAssetState();

            uint256 disputePaymentsLength = dispute.hashlockPayments.length;
            if (disputePaymentsLength == 0) revert NoNewPayments();

            // Allow incremental preimage updates within fixed dispute period (no deadline extension).
            if (paymentsLength != disputePaymentsLength) revert InvalidPaymentsLength();

            bool newPreimageFound = false;
            for (uint256 j = 0; j < paymentsLength;) {
                if (dispute.hashlockPayments[j].preimage == bytes32(0) && hashlockPayments[j].preimage != bytes32(0)) {
                    newPreimageFound = true;
                    dispute.hashlockPayments[j].preimage = hashlockPayments[j].preimage;
                }
                unchecked {
                    ++j;
                }
            }
            if (!newPreimageFound) revert NoNewPreimages();
        }
    }

    /// @notice Validate previous state and update the dispute struct.
    /// @dev Checks stored hash against expected previous state.
    ///      Higher-nonce submissions overwrite the existing dispute because a co-signed state with a
    ///      higher nonce represents a strictly more recent agreement. This is necessary for protocol
    ///      correctness — the dispute must converge to the latest state. No penalty flags are set;
    ///      penalties are handled exclusively by the revocation mechanism.
    ///      The original disputerIsAlice flag is preserved on higher-nonce overrides (only set on
    ///      the initial dispute). This ensures: (a) the penalty mechanism still targets the party
    ///      who initiated the (potentially fraudulent) dispute, even if a third party (watchtower,
    ///      accomplice) overrides the nonce; (b) the non-disputer counterparty retains their
    ///      early-confirmation right regardless of who submitted the override.
    ///      The stored hash is checked against both `onchainNonce` and `nonce` to allow recovery
    ///      from the latest on-chain state by users who lost off-chain state. This is a deliberate
    ///      last-resort recovery mechanism: the recovery attempt is subject to challenge during the
    ///      dispute period and penalty via `penalizeRevokedChannel` if a counterparty or watchtower
    ///      holds a strictly newer co-signed state.
    ///      Individual balances are bound via signatures, not stored hash, to enable off-chain
    ///      reallocations.
    /// @param dispute The dispute storage reference to update.
    /// @param storedStateHash The current on-chain state hash for the asset channel.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param nonce The nonce of the submitted state.
    /// @param onchainNonce The on-chain nonce from the submitted state.
    /// @param aliceBalance Alice's balance in the submitted state.
    /// @param bobBalance Bob's balance in the submitted state.
    /// @param hashlockPaymentsMerkleRoot The Merkle root of hashlock payments.
    /// @param disputePeriod The dispute period duration in seconds.
    ///        Off-chain nodes MUST ensure disputePeriod > 0 before co-signing. Zero allows atomic
    ///        stale-state settlement. The on-chain contract validates uint64 overflow but not minimum.
    function _validatePreviousStateAndUpdateDispute(
        Dispute storage dispute,
        bytes32 storedStateHash,
        address alice,
        address bob,
        uint256 nonce,
        uint256 onchainNonce,
        uint256 aliceBalance,
        uint256 bobBalance,
        bytes32 hashlockPaymentsMerkleRoot,
        uint64 disputePeriod
    ) private {
        uint256 balanceSum = aliceBalance + bobBalance;

        // NOTE: We also check against nonce instead of onchainNonce to allow settling from states
        //       that were recovered from the latest on-chain state.
        if (
            storedStateHash != keccak256(abi.encodePacked(onchainNonce, balanceSum, alice))
                && storedStateHash != keccak256(abi.encodePacked(onchainNonce, balanceSum, bob))
                && storedStateHash != keccak256(abi.encodePacked(nonce, balanceSum, alice))
                && storedStateHash != keccak256(abi.encodePacked(nonce, balanceSum, bob))
        ) {
            revert InvalidPreviousState();
        }

        dispute.nonce = nonce;
        dispute.balances.alice = aliceBalance;
        dispute.balances.bob = bobBalance;
        dispute.hashlockPaymentsMerkleRoot = hashlockPaymentsMerkleRoot;

        // Only set disputer on the initial dispute (disputeDeadline == 0), not on higher-nonce
        // overrides. Preserving the original disputer ensures:
        // 1. The penalty mechanism still targets the party who initiated the (potentially
        //    fraudulent) dispute, even if a third party or watchtower overrides the nonce.
        // 2. The non-disputer counterparty retains their early-confirmation right regardless
        //    of who submitted the higher-nonce override.
        if (dispute.disputeDeadline == 0) {
            dispute.disputerIsAlice = (msg.sender == alice);
        }
        uint256 deadline = block.timestamp + uint256(disputePeriod);
        if (deadline > type(uint64).max) revert InvalidDisputePeriod();
        // casting to 'uint64' is safe because `deadline` is checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        dispute.disputeDeadline = uint64(deadline);
    }

    /// @notice Confirm unilateral settlement for multiple assets after dispute period.
    /// @dev Distributes funds per final balances, adjusted for resolved HTLCs.
    ///      Fraudulent party loses to disputer; consolidates if same recipient.
    ///      Clears storage after distribution.
    /// @param store The global storage struct.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param assetVariants Array of asset variants.
    /// @param assetAddresses Array of asset addresses.
    /// @param tokenNumberIds Array of token IDs (0 for fungibles).
    /// @return assetDistributions Array of distributions (amounts, recipients).
    function confirmUnilateralSettlement(
        Storage storage store,
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant[] memory assetVariants,
        address[] memory assetAddresses,
        uint256[] memory tokenNumberIds
    ) internal returns (AssetDistribution[] memory assetDistributions) {
        uint256 length = assetVariants.length;
        if (assetAddresses.length != length || tokenNumberIds.length != length) revert LengthMismatch();

        assetDistributions = new AssetDistribution[](length);

        for (uint256 i = 0; i < length;) {
            assetDistributions[i] = _confirmAssetUnilateralSettlement(
                store, alice, bob, channelNumber, assetVariants[i], assetAddresses[i], tokenNumberIds[i]
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Confirm unilateral settlement for multiple assets using calldata for gas efficiency.
    /// @dev Calldata variant; identical to memory version.
    /// @param store The global storage struct.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param assetVariants Array of asset variants.
    /// @param assetAddresses Array of asset addresses.
    /// @param tokenNumberIds Array of token IDs (0 for fungibles).
    /// @return assetDistributions Array of distributions (amounts, recipients).
    function confirmUnilateralSettlementCalldata(
        Storage storage store,
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant[] calldata assetVariants,
        address[] calldata assetAddresses,
        uint256[] calldata tokenNumberIds
    ) internal returns (AssetDistribution[] memory assetDistributions) {
        uint256 length = assetVariants.length;
        if (assetAddresses.length != length || tokenNumberIds.length != length) revert LengthMismatch();

        assetDistributions = new AssetDistribution[](length);

        for (uint256 i = 0; i < length;) {
            assetDistributions[i] = _confirmAssetUnilateralSettlement(
                store, alice, bob, channelNumber, assetVariants[i], assetAddresses[i], tokenNumberIds[i]
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Confirm settlement for a single asset.
    /// @dev Only the non-disputer counterparty can settle before the deadline; all others must wait
    ///      for the dispute period to expire. Adjusts balances for resolved HTLCs (unresolved remain
    ///      in original balances). No fraud redirect — fraud penalties are handled exclusively by the
    ///      revocation mechanism (penalizeRevokedChannel). Clears storage after distribution.
    ///
    ///      **Anti-griefing**: The beneficiary who is also `msg.sender` is paid directly; all other
    ///      payouts are moved into `store.claimable`. This keeps settlement finalizable without
    ///      depending on the counterparty's receive behavior.
    ///
    ///      **WithdrawSetting not used**: Settlement confirmation resolves balances to the
    ///      participants themselves, either via direct payout to the beneficiary caller or via
    ///      `claimable` escrow for later withdrawal. The `WithdrawSetting` from the co-signed
    ///      state is not stored in the `Dispute` struct and is therefore unavailable at
    ///      confirmation time. This is by design: during a unilateral (adversarial) settlement,
    ///      routing to the liquidity pool would require additional storage and could disadvantage
    ///      a party who expects wallet delivery. Parties who prefer pool routing can transfer
    ///      funds from their wallet to the pool after settlement.
    /// @param store The global storage struct.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber Channel number.
    /// @param assetVariant Asset variant.
    /// @param assetAddress Asset address.
    /// @param tokenNumberId Token ID.
    /// @return assetDistribution The distribution details.
    function _confirmAssetUnilateralSettlement(
        Storage storage store,
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId
    ) internal returns (AssetDistribution memory assetDistribution) {
        bytes32 assetChannelId = keccak256(
            abi.encodePacked(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId)
        );
        Dispute storage dispute = store.assetDisputes[assetChannelId];
        if (dispute.disputeDeadline == 0) revert NotInDispute();

        // Early settle only if caller is the non-disputer counterparty.
        // disputerIsAlice and disputeDeadline are packed in the same slot → single SLOAD.
        {
            bool disputerIsAlice = dispute.disputerIsAlice;
            if (!(disputerIsAlice ? msg.sender == bob : msg.sender == alice)) {
                if (block.timestamp < dispute.disputeDeadline) revert DisputePeriodNotPassed();
            }
        }

        uint256 aliceAmount = dispute.balances.alice;
        uint256 bobAmount = dispute.balances.bob;

        // Resolve HTLCs and compute net settlement
        (aliceAmount, bobAmount) = _resolveHTLCs(dispute, aliceAmount, bobAmount);

        // Clear storage before transfers (CEI pattern)
        // Sentinel prevents signature replay across channel incarnations
        store.assetChannels[assetChannelId] = CLOSED_CHANNEL_SENTINEL;
        delete store.assetDisputes[assetChannelId];

        // Distribute deterministically: direct only to the caller's own allocation.
        if (aliceAmount > 0) {
            if (msg.sender == alice) {
                LithiumTransfer.withdrawAssetTo(alice, assetVariant, assetAddress, tokenNumberId, aliceAmount);
            } else {
                store.claimable[
                        alice
                    ][keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId))] += aliceAmount;
            }
        }
        if (bobAmount > 0) {
            if (msg.sender == bob) {
                LithiumTransfer.withdrawAssetTo(bob, assetVariant, assetAddress, tokenNumberId, bobAmount);
            } else {
                store.claimable[
                        bob
                    ][keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId))] += bobAmount;
            }
        }

        assetDistribution = AssetDistribution({
            assetVariant: assetVariant,
            assetAddress: assetAddress,
            tokenNumberId: tokenNumberId,
            aliceAmount: aliceAmount,
            bobAmount: bobAmount,
            aliceRecipient: alice,
            bobRecipient: bob
        });
    }

    /// @notice Resolve HTLC payments and return adjusted balances.
    /// @dev Iterates through dispute payments, tallies sends per direction, and nets balances.
    ///      **Offchain responsibility**: `aliceSent` and `bobSent` accumulate HTLC amounts using
    ///      checked arithmetic (`+=`). If the cumulative HTLC amounts overflow `uint256`, the
    ///      transaction reverts. The offchain node MUST ensure that the total sum of HTLC amounts
    ///      per direction fits within `uint256` — in practice, this is trivially satisfied since
    ///      real token supplies are far below 2^256. Combined with the offchain HTLC count cap
    ///      (50–100 per asset per state), overflow is not a practical concern.
    ///
    ///      **Netting clipping**: When net obligations exceed a party's available balance (e.g.,
    ///      HTLC net > aliceBalance), the transfer is clipped to the available amount and the
    ///      deficit is forfeited. This ensures the total distributed never exceeds the channel
    ///      capacity (balanceSum is conserved). The offchain node SHOULD ensure HTLC amounts are
    ///      reasonable relative to channel balances to avoid clipping.
    /// @param dispute The dispute storage reference.
    /// @param aliceAmount Alice's base balance.
    /// @param bobAmount Bob's base balance.
    /// @return adjustedAlice Alice's balance after HTLC resolution.
    /// @return adjustedBob Bob's balance after HTLC resolution.
    function _resolveHTLCs(Dispute storage dispute, uint256 aliceAmount, uint256 bobAmount)
        private
        view
        returns (uint256, uint256)
    {
        uint256 netAlice = 0; // net amount Alice owes (Alice sent more)
        uint256 netBob = 0; // net amount Bob owes (Bob sent more)
        {
            uint256 aliceSent = 0;
            uint256 bobSent = 0;
            uint256 paymentsLength = dispute.hashlockPayments.length;
            for (uint256 j; j < paymentsLength;) {
                HashlockPayment storage payment = dispute.hashlockPayments[j];
                if (payment.preimage != bytes32(0)) {
                    if (payment.direction == PaymentDirection.BobToAlice) bobSent += payment.amount;
                    else aliceSent += payment.amount;
                }
                unchecked {
                    ++j;
                }
            }

            unchecked {
                if (aliceSent > bobSent) netAlice = aliceSent - bobSent;
                else if (bobSent > aliceSent) netBob = bobSent - aliceSent;
            }
        }

        // Netting arithmetic is safe unchecked:
        // - Subtractions are guarded by strict-greater-than checks.
        // - Additions cannot overflow: in every branch the sum
        //   (aliceAmount + bobAmount) is at most the original balanceSum,
        //   which was validated with checked arithmetic at dispute creation.
        if (netAlice > 0) {
            if (aliceAmount > netAlice) {
                unchecked {
                    aliceAmount -= netAlice;
                    bobAmount += netAlice;
                }
            } else {
                unchecked {
                    bobAmount += aliceAmount;
                }
                aliceAmount = 0;
            }
        } else if (netBob > 0) {
            if (bobAmount > netBob) {
                unchecked {
                    bobAmount -= netBob;
                    aliceAmount += netBob;
                }
            } else {
                unchecked {
                    aliceAmount += bobAmount;
                }
                bobAmount = 0;
            }
        }

        return (aliceAmount, bobAmount);
    }
}
