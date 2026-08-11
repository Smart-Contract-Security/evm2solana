// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {
    ILithium,
    Storage,
    ChannelConfig,
    SignedAssetState,
    AssetVariant,
    HashlockPayment,
    SignedRevocation,
    AssetDistribution,
    BatchOp,
    OpType,
    Dispute,
    EthTxValueMismatch,
    InvalidOpType
} from "./interfaces/ILithium.sol";
import {LithiumTransfer} from "./libraries/LithiumTransfer.sol";
import {LithiumUpdater} from "./libraries/LithiumUpdater.sol";
import {LithiumSettler} from "./libraries/LithiumSettler.sol";
import {LithiumRevoker} from "./libraries/LithiumRevoker.sol";

/// @title Lithium
/// @author Hydranet
/// @notice Lithium is a payment channel contract that allows two participants to
///         open a channel and deposit funds into it. After the channel is opened,
///         the participants can send payments to each other offchain. The funds
///         in the channel can be settled onchain at any time by the participants,
///         either cooperatively or unilaterally. In case of malicious behavior
///         when settling unilaterally, the counterparty has time until the dispute
///         period is over to submit the latest channel state and the payment
///         preimages for the pending hash-locked payments.
///         Lithium supports multiple assets in the same channel.
/// @dev This contract delegates core logic to libraries for modularity and gas efficiency.
contract Lithium is ILithium, ERC721Holder, ERC1155Holder, ReentrancyGuardTransient {
    Storage internal store;

    /// @inheritdoc ILithium
    function updateChannel(ChannelConfig calldata channelConfig, SignedAssetState[] calldata assetStates)
        external
        payable
        nonReentrant
    {
        uint256 ethRequired = LithiumUpdater.updateChannelCalldata(store, channelConfig, assetStates);

        if (ethRequired != msg.value) revert EthTxValueMismatch();
    }

    /// @inheritdoc ILithium
    function unilateralSettleChannel(
        ChannelConfig calldata channelConfig,
        SignedAssetState[] calldata assetStates,
        HashlockPayment[][] calldata hashlockPaymentsArray
    ) external nonReentrant {
        LithiumSettler.unilateralSettleChannelCalldata(store, channelConfig, assetStates, hashlockPaymentsArray);
    }

    /// @inheritdoc ILithium
    function confirmUnilateralSettlement(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant[] calldata assetVariants,
        address[] calldata assetAddresses,
        uint256[] calldata tokenNumberIds
    ) external nonReentrant {
        AssetDistribution[] memory assetDistributions =
            LithiumSettler.confirmUnilateralSettlementCalldata(
                store, alice, bob, channelNumber, assetVariants, assetAddresses, tokenNumberIds
            );

        emit AssetsDistributed(assetDistributions);
    }

    /// @inheritdoc ILithium
    function penalizeRevokedChannel(
        address alice,
        address bob,
        uint256 channelNumber,
        SignedRevocation[] calldata revocations
    ) external nonReentrant {
        AssetDistribution[] memory assetDistributions =
            LithiumRevoker.penalizeRevokedChannelCalldata(store, alice, bob, channelNumber, revocations);

        emit AssetsDistributed(assetDistributions);
    }

    /// @inheritdoc ILithium
    function depositToPool(AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId, uint256 amount)
        external
        payable
        nonReentrant
    {
        uint256 ethRequired = LithiumTransfer.depositToPool(store, assetVariant, assetAddress, tokenNumberId, amount);
        if (ethRequired != msg.value) revert EthTxValueMismatch();
    }

    /// @inheritdoc ILithium
    function withdrawFromPool(AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId, uint256 amount)
        external
        nonReentrant
    {
        LithiumTransfer.withdrawFromPool(store, assetVariant, assetAddress, tokenNumberId, amount);
    }

    /// @inheritdoc ILithium
    function claimAsset(AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId) external nonReentrant {
        LithiumTransfer.claimAsset(store, assetVariant, assetAddress, tokenNumberId);
    }

    /// @inheritdoc ILithium
    function batchExecute(BatchOp[] calldata ops) external payable nonReentrant {
        uint256 length = ops.length;
        uint256 ethRequired = 0;

        for (uint256 i = 0; i < length;) {
            BatchOp calldata op = ops[i];
            bytes calldata data = op.data;

            if (op.opType == OpType.UpdateChannel) {
                (ChannelConfig memory channelConfig, SignedAssetState[] memory assetStates) =
                    abi.decode(data, (ChannelConfig, SignedAssetState[]));
                ethRequired += LithiumUpdater.updateChannel(store, channelConfig, assetStates);
            } else if (op.opType == OpType.UnilateralSettleChannel) {
                (
                    ChannelConfig memory channelConfig,
                    SignedAssetState[] memory assetStates,
                    HashlockPayment[][] memory hashlockPaymentsArray
                ) = abi.decode(data, (ChannelConfig, SignedAssetState[], HashlockPayment[][]));
                LithiumSettler.unilateralSettleChannel(store, channelConfig, assetStates, hashlockPaymentsArray);
            } else if (op.opType == OpType.ConfirmUnilateralSettlement) {
                (
                    address alice,
                    address bob,
                    uint256 channelNumber,
                    AssetVariant[] memory assetVariants,
                    address[] memory assetAddresses,
                    uint256[] memory tokenNumberIds
                ) = abi.decode(data, (address, address, uint256, AssetVariant[], address[], uint256[]));
                AssetDistribution[] memory distributions = LithiumSettler.confirmUnilateralSettlement(
                    store, alice, bob, channelNumber, assetVariants, assetAddresses, tokenNumberIds
                );
                emit AssetsDistributed(distributions);
            } else if (op.opType == OpType.PenalizeRevokedChannel) {
                (address alice, address bob, uint256 channelNumber, SignedRevocation[] memory revocations) =
                    abi.decode(data, (address, address, uint256, SignedRevocation[]));
                AssetDistribution[] memory distributions =
                    LithiumRevoker.penalizeRevokedChannel(store, alice, bob, channelNumber, revocations);
                emit AssetsDistributed(distributions);
            } else if (op.opType == OpType.DepositToPool) {
                (AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId, uint256 amount) =
                    abi.decode(data, (AssetVariant, address, uint256, uint256));
                ethRequired += LithiumTransfer.depositToPool(store, assetVariant, assetAddress, tokenNumberId, amount);
            } else if (op.opType == OpType.WithdrawFromPool) {
                (AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId, uint256 amount) =
                    abi.decode(data, (AssetVariant, address, uint256, uint256));
                LithiumTransfer.withdrawFromPool(store, assetVariant, assetAddress, tokenNumberId, amount);
            } else if (op.opType == OpType.ClaimAsset) {
                (AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId) =
                    abi.decode(data, (AssetVariant, address, uint256));
                LithiumTransfer.claimAsset(store, assetVariant, assetAddress, tokenNumberId);
            } else {
                revert InvalidOpType();
            }

            unchecked {
                ++i;
            }
        }

        if (ethRequired != msg.value) revert EthTxValueMismatch();
    }

    /// @inheritdoc ILithium
    function getLiquidity(address provider, AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId)
        external
        view
        returns (uint256 liquidity)
    {
        liquidity =
            store.liquidityPool[provider][keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId))];
    }

    /// @inheritdoc ILithium
    function getAssetDispute(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId
    ) external view returns (Dispute memory dispute) {
        dispute = store.assetDisputes[
            keccak256(abi.encodePacked(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId))
        ];
    }

    /// @inheritdoc ILithium
    function getAssetChannel(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId
    ) external view returns (bytes32 assetChannel) {
        bytes32 assetChannelId = keccak256(
            abi.encodePacked(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId)
        );
        assetChannel = store.assetChannels[assetChannelId];
    }

    /// @inheritdoc ILithium
    function getClaimable(address user, AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId)
        external
        view
        returns (uint256 amount)
    {
        amount = store.claimable[user][keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId))];
    }

    /// @inheritdoc ILithium
    receive() external payable nonReentrant {
        LithiumTransfer.depositToPool(store, AssetVariant.Native, address(0), 0, msg.value);
    }

    /// @notice ERC165: Reports support for IERC721Receiver in addition to IERC1155Receiver.
    /// @dev ERC1155Holder already registers IERC1155Receiver via ERC165. This override adds
    ///      IERC721Receiver support, which ERC721Holder implements but does not register.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
