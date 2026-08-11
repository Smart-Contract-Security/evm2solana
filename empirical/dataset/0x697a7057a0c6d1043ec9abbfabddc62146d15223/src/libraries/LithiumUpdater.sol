// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    Storage,
    ChannelConfig,
    SignedAssetState,
    AssetState,
    AssetVariant,
    WithdrawSetting,
    Dispute,
    InvalidChannelParticipants,
    InvalidSender,
    InvalidPreviousState,
    InvalidNonce,
    InvalidAssetState,
    InDispute
} from "../interfaces/ILithium.sol";
import {LithiumVerification} from "./LithiumVerification.sol";
import {LithiumTransfer} from "./LithiumTransfer.sol";

library LithiumUpdater {
    /// @notice Batch aggregation for multiple asset channel updates in a single transaction.
    ///         Each AssetState is signed individually by both parties.
    ///         Allows deposits, withdrawals, and balance reallocations.
    /// @dev Memory variant used by batchExecute. Verifies signatures, validates states,
    ///      processes balance changes. Returns total ETH required; caller must provide msg.value.
    /// @param store The global storage struct.
    /// @param channelConfig The channel configuration.
    /// @param signedAssetStates Array of new asset states with signatures.
    /// @return ethRequired The total ETH required for Native deposits.
    function updateChannel(
        Storage storage store,
        ChannelConfig memory channelConfig,
        SignedAssetState[] memory signedAssetStates
    ) internal returns (uint256 ethRequired) {
        if (channelConfig.alice == channelConfig.bob) {
            revert InvalidChannelParticipants();
        }
        if (msg.sender != channelConfig.alice && msg.sender != channelConfig.bob) revert InvalidSender();

        mapping(bytes32 => uint256) storage aliceLiq = store.liquidityPool[channelConfig.alice];
        mapping(bytes32 => uint256) storage bobLiq = store.liquidityPool[channelConfig.bob];

        uint256 length = signedAssetStates.length;
        for (uint256 i = 0; i < length;) {
            SignedAssetState memory signedAssetState = signedAssetStates[i];

            LithiumVerification.verifyAssetChannelStateSignatures(channelConfig, signedAssetState);

            AssetState memory assetState = signedAssetState.assetState;

            ethRequired += _updateAssetChannel(
                store,
                aliceLiq,
                bobLiq,
                channelConfig.alice,
                channelConfig.bob,
                channelConfig.channelNumber,
                assetState.withdrawSetting,
                assetState.assetVariant,
                assetState.assetAddress,
                assetState.tokenNumberId,
                assetState.nonce,
                assetState.onchainNonce,
                assetState.balances.alice,
                assetState.balances.bob,
                assetState.previousBalances.alice,
                assetState.previousBalances.bob
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch aggregation for multiple asset channel updates in a single transaction.
    ///         Each AssetState is signed individually by both parties.
    ///         Allows deposits, withdrawals, and balance reallocations.
    /// @dev Calldata variant for external calls; identical logic to memory version.
    /// @param store The global storage struct.
    /// @param channelConfig The channel configuration.
    /// @param signedAssetStates Array of new asset states with signatures.
    /// @return ethRequired The total ETH required for Native deposits.
    function updateChannelCalldata(
        Storage storage store,
        ChannelConfig calldata channelConfig,
        SignedAssetState[] calldata signedAssetStates
    ) internal returns (uint256 ethRequired) {
        if (channelConfig.alice == channelConfig.bob) {
            revert InvalidChannelParticipants();
        }
        if (msg.sender != channelConfig.alice && msg.sender != channelConfig.bob) revert InvalidSender();

        mapping(bytes32 => uint256) storage aliceLiq = store.liquidityPool[channelConfig.alice];
        mapping(bytes32 => uint256) storage bobLiq = store.liquidityPool[channelConfig.bob];

        uint256 length = signedAssetStates.length;
        for (uint256 i = 0; i < length;) {
            SignedAssetState calldata signedAssetState = signedAssetStates[i];

            LithiumVerification.verifyAssetChannelStateSignaturesCalldata(channelConfig, signedAssetState);

            AssetState calldata assetState = signedAssetState.assetState;

            ethRequired += _updateAssetChannel(
                store,
                aliceLiq,
                bobLiq,
                channelConfig.alice,
                channelConfig.bob,
                channelConfig.channelNumber,
                assetState.withdrawSetting,
                assetState.assetVariant,
                assetState.assetAddress,
                assetState.tokenNumberId,
                assetState.nonce,
                assetState.onchainNonce,
                assetState.balances.alice,
                assetState.balances.bob,
                assetState.previousBalances.alice,
                assetState.previousBalances.bob
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Updates an individual asset channel state.
    /// @dev Validates previous state hash and balance sums; processes balance changes via deposits/withdrawals;
    ///      stores new state hash. Nonce must strictly exceed onchainNonce (enforced in this function).
    ///      Balance differences are reconciled via deposits from wallet/pool or withdrawals to wallet/pool.
    /// @param store The global storage struct.
    /// @param aliceLiq Alice's liquidity mapping.
    /// @param bobLiq Bob's liquidity mapping.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param withdrawSetting The withdraw setting for this asset state.
    /// @param assetVariant The asset variant.
    /// @param assetAddress The asset contract address.
    /// @param tokenNumberId The token ID (0 for ETH/ERC20).
    /// @param nonce The nonce of the new state.
    /// @param onchainNonce The nonce of the previous state.
    /// @param aliceBalance Alice's balance in the new state.
    /// @param bobBalance Bob's balance in the new state.
    /// @param prevAliceBalance Alice's balance in the previous state.
    /// @param prevBobBalance Bob's balance in the previous state.
    /// @return ethDelta ETH required for Native deposits.
    function _updateAssetChannel(
        Storage storage store,
        mapping(bytes32 => uint256) storage aliceLiq,
        mapping(bytes32 => uint256) storage bobLiq,
        address alice,
        address bob,
        uint256 channelNumber,
        WithdrawSetting withdrawSetting,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        uint256 nonce,
        uint256 onchainNonce,
        uint256 aliceBalance,
        uint256 bobBalance,
        uint256 prevAliceBalance,
        uint256 prevBobBalance
    ) internal returns (uint256 ethDelta) {
        uint256 prevBalanceSum = prevAliceBalance + prevBobBalance;
        uint256 balanceSum = aliceBalance + bobBalance;

        bytes32 assetChannelId =
            keccak256(abi.encodePacked(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId));

        // Check if currently in a dispute; if so, disallow updates
        Dispute storage dispute = store.assetDisputes[assetChannelId];
        if (dispute.disputeDeadline > 0) revert InDispute();

        // updateChannel is for deposits/withdrawals only — it must change the channel capacity.
        if (balanceSum == prevBalanceSum) revert InvalidAssetState();

        bytes32 currentPrev = store.assetChannels[assetChannelId];
        if (currentPrev != bytes32(0)) {
            // Not the first state update; validate previous state
            if (
                currentPrev != keccak256(abi.encodePacked(onchainNonce, prevBalanceSum, alice))
                    && currentPrev != keccak256(abi.encodePacked(onchainNonce, prevBalanceSum, bob))
            ) revert InvalidPreviousState();
        } else {
            // First state update; previous balances must be zero
            if (prevBalanceSum != 0) revert InvalidPreviousState();
        }

        // Enforce nonce monotonicity relative to the provided on-chain nonce: updates must advance state.
        if (nonce <= onchainNonce) revert InvalidNonce();

        // Store new state hash (nonce + sum + updater for efficiency; balance split bound by signatures)
        store.assetChannels[assetChannelId] = keccak256(abi.encodePacked(nonce, balanceSum, msg.sender));

        // Precompute liquidity key once for both participants
        bytes32 liquidityKey = keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId));

        // Process Alice's changes
        ethDelta = LithiumTransfer.processBalanceChanges(
            liquidityKey,
            assetVariant,
            assetAddress,
            tokenNumberId,
            alice,
            aliceLiq,
            aliceBalance,
            prevAliceBalance,
            withdrawSetting == WithdrawSetting.AliceToWalletBobToWallet
                || withdrawSetting == WithdrawSetting.AliceToWalletBobToPool
        );

        // Process Bob's changes
        ethDelta += LithiumTransfer.processBalanceChanges(
            liquidityKey,
            assetVariant,
            assetAddress,
            tokenNumberId,
            bob,
            bobLiq,
            bobBalance,
            prevBobBalance,
            withdrawSetting == WithdrawSetting.AliceToWalletBobToWallet
                || withdrawSetting == WithdrawSetting.AliceToPoolBobToWallet
        );
    }
}
