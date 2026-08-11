// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {
    UUPSUpgradeable
} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/VRFConsumerBaseV2.sol";

import "./interface/IFlooring.sol";
import "./interface/IFlooringEvent.sol";
import "./interface/IFragmentToken.sol";

import "./logic/CollectionKey.sol";
import "./logic/User.sol";
import "./logic/Collection.sol";
import "./logic/Auction.sol";
import "./logic/Raffle.sol";
import "./logic/PrivateOffer.sol";
import {
    CollectionState,
    UserFloorAccount,
    FeeConfig
} from "./logic/Structs.sol";
import "./base/Multicall.sol";
import "./Errors.sol";
import { TrustedUpgradeable } from "./library/TrustedUpgradeable.sol";
import { Pausable } from "./library/Pausable.sol";

contract Flooring is
    IFlooring,
    IFlooringEvent,
    Multicall,
    TrustedUpgradeable,
    UUPSUpgradeable,
    VRFConsumerBaseV2,
    Pausable
{
    using CollectionLib for CollectionState;
    using AuctionLib for CollectionState;
    using RaffleLib for CollectionState;
    using PrivateOfferLib for CollectionState;
    using UserLib for UserFloorAccount;
    using CollectionKeyLib for CollectionKey;

    struct RandomRequestInfo {
        uint96 typ;
        address collection;
        bytes data;
    }

    /// Information related to Chainlink VRF Randomness Oracle.

    /// The keyhash, which is network dependent.
    bytes32 internal immutable keyHash;
    /// Subscription Id, need to get from the Chainlink UI.
    uint64 internal immutable subId;
    /// Chainlink VRF Coordinator.
    VRFCoordinatorV2Interface internal immutable COORDINATOR;

    /// A mapping from VRF request Id to raffle.
    mapping(uint256 requestId => RandomRequestInfo requestInfo)
        internal randomnessRequestToReceiver;

    /// This should be the FLC token.
    address public immutable creditToken;

    /// A mapping from collection id to `CollectionState`.
    mapping(address collectionId => CollectionState state)
        internal collectionStates;

    /// A mapping from user address to the `UserFloorAccount`s.
    mapping(address walletAddr => UserFloorAccount account)
        internal userFloorAccounts;

    /// A mapping of supported ERC-20 token.
    mapping(address tokenAddr => bool isSupported) internal supportedTokens;

    /// A mapping from Proxy Collection(wrapped) to underlying Collection.
    /// eg. Paraspace Derivative Token BAYC(nBAYC) -> BAYC
    /// Note. we only use proxy collection to transfer NFTs,
    ///       all other operations should use underlying Collection.(State, Log, CollectionAccount)
    ///       proxy collection has not `CollectionState`, but use underlying collection's state.
    ///       proxy collection only is used to lock infinitly.
    ///       `fragmentNFTs` and `claimRandomNFT` don't support proxy collection
    ///       Currently, proxy collection id and proxy collection contract address should be same
    mapping(address proxyCollectionId => address underlyingCollectionId)
        internal collectionProxy;

    /// A mapping of collection fees configuration
    /// For different tokens, we may charge different fees
    mapping(address collectionId => mapping(address tokenAddr => FeeConfig fees))
        internal collectionFees;

    /// @dev Function IDs so that we can pause individual functions
    uint256 internal pausedFuncIds;

    constructor(
        bytes32 _keyHash,
        uint64 _subId,
        address _vrfCoordinator,
        address flcToken
    ) payable VRFConsumerBaseV2(_vrfCoordinator) {
        keyHash = _keyHash;
        subId = _subId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        creditToken = flcToken;

        // _disableInitializers();
    }

    /// required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// required by the pausable
    function _pauser() internal view virtual override returns (address) {
        return owner;
    }

    /// required by the pausable
    function _funcIds() internal view virtual override returns (uint256) {
        return pausedFuncIds;
    }

    /// required by the pausable
    function _setFuncIds(uint256 funcIds) internal virtual override {
        pausedFuncIds = funcIds;
    }

    /// @dev just declare this as payable to reduce gas and bytecode
    function initialize() public payable initializer {
        __Trusted_init();
        __UUPSUpgradeable_init();
    }

    function supportNewCollection(
        NewCollectionParam calldata param
    ) public payable onlyTrusted {
        CollectionState storage collection = collectionStates[
            param.collectionId
        ];
        bool notExist = collection.nextKeyId == 0;
        /// incr without checking whether they are exist or not
        ++collection.nextKeyId;
        ++collection.nextActivityId;
        collection.floorToken = IFragmentToken(param.fragmentToken);
        collection._contractAddr = param.contractAddr;
        if (notExist) {
            emit NewCollectionSupported(
                param.collectionId,
                param.fragmentToken
            );
        }
    }

    function supportNewToken(
        address _token,
        bool addOrRemove
    ) public payable onlyTrusted {
        if (supportedTokens[_token] == addOrRemove) {
            return;
        } else {
            /// true - add
            /// false - remove
            supportedTokens[_token] = addOrRemove;
            emit UpdateTokenSupported(_token, addOrRemove);
        }
    }

    function updateCollectionFees(
        address collectionId,
        address[] calldata tokens,
        FeeConfig[] calldata fees
    ) public payable onlyTrusted {
        for (uint256 i; i < tokens.length; ) {
            collectionFees[collectionId][tokens[i]] = fees[i];
            unchecked {
                ++i;
            }
        }
    }

    function setCollectionProxy(
        address proxyCollection,
        address underlying
    ) public payable onlyTrusted {
        if (collectionProxy[proxyCollection] == underlying) {
            return;
        } else {
            collectionProxy[proxyCollection] = underlying;
            emit ProxyCollectionChanged(proxyCollection, underlying);
        }
    }

    function withdrawPlatformFee(
        address token,
        uint256 amount
    ) public payable onlyTrusted {
        /// track platform fee with account, only can withdraw fee accumulated during tx.
        /// no need to check credit token balance for the account.
        UserFloorAccount storage userFloorAccount = userFloorAccounts[
            address(this)
        ];
        userFloorAccount.withdraw(msg.sender, token, amount, false);
    }

    function addAndLockCredit(
        address onBehalfOf,
        uint256 amount
    ) public payable onlyTrusted {
        UserFloorAccount storage userFloorAccount = userFloorAccounts[
            onBehalfOf
        ];
        userFloorAccount.deposit(onBehalfOf, creditToken, amount, true);
    }

    function unlockCredit(
        address receiver,
        uint256 amount
    ) public payable onlyTrusted {
        UserFloorAccount storage userFloorAccount = userFloorAccounts[receiver];
        userFloorAccount.unlockCredit(amount);
    }

    function addTokens(
        address onBehalfOf,
        address token,
        uint256 amount
    ) public payable whenNotPaused(1) {
        mustSupportedToken(token);

        UserFloorAccount storage userFloorAccount = userFloorAccounts[
            onBehalfOf
        ];
        userFloorAccount.deposit(onBehalfOf, token, amount, false);
    }

    function removeTokens(
        address token,
        uint256 amount,
        address receiver
    ) public whenNotPaused(2) {
        UserFloorAccount storage userFloorAccount = userFloorAccounts[
            msg.sender
        ];
        userFloorAccount.withdraw(
            receiver,
            token,
            amount,
            token == creditToken
        );
    }

    function lockNFTs(
        CollectionKey key,
        uint256[] memory nftIds,
        uint256 expiryTs,
        uint256 vipLevel,
        uint256 maxCreditCost,
        address onBehalfOf
    ) public whenNotPaused(3) returns (uint256) {
        mustValidNftIds(nftIds);
        mustValidExpiryTs(expiryTs);
        /// only check the first and the last elems as `nftIds` are in ascending order
        if (!key.isValidTokenList(nftIds[0], nftIds[nftIds.length - 1]))
            revert Errors.InvalidParam();

        address collectionId = key.id();
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        return
            collectionState.lockNfts(
                userFloorAccounts[onBehalfOf],
                LockParam({
                    proxyCollectionId: collectionId,
                    collectionId: underlying,
                    creditToken: creditToken,
                    nftIds: nftIds,
                    expiryTs: expiryTs,
                    vipLevel: uint8(vipLevel),
                    maxCreditCost: maxCreditCost
                }),
                onBehalfOf
            );
    }

    function unlockNFTs(
        address collectionId,
        uint256 expiryTs,
        uint256[] memory nftIds,
        address receiver
    ) public whenNotPaused(4) {
        mustValidNftIds(nftIds);

        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.unlockNfts(
            userFloorAccounts[msg.sender],
            collectionId,
            underlying,
            nftIds,
            expiryTs,
            receiver
        );
    }

    function extendKeys(
        address collectionId,
        uint256[] memory nftIds,
        uint256 expiryTs,
        uint256 newVipLevel,
        uint256 maxCreditCost
    ) public whenNotPaused(5) returns (uint256) {
        mustValidNftIds(nftIds);
        mustValidExpiryTs(expiryTs);

        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        return
            collectionState.extendLockingForKeys(
                userFloorAccounts[msg.sender],
                LockParam({
                    proxyCollectionId: collectionId,
                    collectionId: underlying,
                    creditToken: creditToken,
                    nftIds: nftIds,
                    expiryTs: expiryTs,
                    vipLevel: uint8(newVipLevel),
                    maxCreditCost: maxCreditCost
                })
            );
    }

    function tidyExpiredNFTs(
        address collectionId,
        uint256[] memory nftIds
    ) public whenNotPaused(6) {
        mustValidNftIds(nftIds);
        /// expired safeboxes must not be collection
        CollectionState storage collectionState = useCollectionState(
            collectionId
        );
        collectionState.tidyExpiredNFTs(nftIds, collectionId);
    }

    function fragmentNFTs(
        CollectionKey key,
        uint256[] memory nftIds,
        address onBehalfOf
    ) public whenNotPaused(7) {
        mustValidNftIds(nftIds);
        /// only check the first and the last elems as `nftIds` are in ascending order
        if (!key.isValidTokenList(nftIds[0], nftIds[nftIds.length - 1]))
            revert Errors.InvalidParam();

        CollectionState storage collectionState = useCollectionState(key.id());

        collectionState.fragmentNFTs(
            userFloorAccounts[onBehalfOf],
            key.id(),
            nftIds,
            onBehalfOf
        );
    }

    function claimRandomNFT(
        address collectionId,
        uint256 claimCnt,
        uint256 maxCreditCost,
        address receiver
    ) public whenNotPaused(8) returns (uint256) {
        CollectionState storage collectionState = useCollectionState(
            collectionId
        );

        return
            collectionState.claimRandomNFT(
                userFloorAccounts,
                collectionFees[collectionId],
                collectionId,
                claimCnt,
                maxCreditCost,
                receiver
            );
    }

    function initAuctionOnVault(
        address collectionId,
        uint256[] memory vaultIdx,
        address bidToken,
        uint96 bidAmount
    ) public whenNotPaused(9) {
        mustValidNftIds(vaultIdx);
        CollectionState storage collectionState = useCollectionState(
            collectionId
        );
        collectionState.initAuctionOnVault(
            userFloorAccounts,
            collectionFees[collectionId][bidToken],
            creditToken,
            collectionId,
            vaultIdx,
            bidToken,
            bidAmount
        );
    }

    function initAuctionOnExpiredSafeBoxes(
        address collectionId,
        uint256[] memory nftIds,
        address bidToken,
        uint256 bidAmount
    ) public whenNotPaused(10) {
        mustValidNftIds(nftIds);
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.initAuctionOnExpiredSafeBoxes(
            userFloorAccounts,
            collectionFees[underlying][bidToken],
            creditToken,
            underlying,
            nftIds,
            bidToken,
            bidAmount
        );
    }

    function ownerInitAuctions(
        address collectionId,
        uint256[] memory nftIds,
        uint256 maxExpiry,
        address token,
        uint256 minimumBid
    ) public whenNotPaused(11) {
        mustValidNftIds(nftIds);

        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.ownerInitAuctions(
            userFloorAccounts,
            collectionFees[underlying][token],
            creditToken,
            underlying,
            nftIds,
            maxExpiry,
            token,
            minimumBid
        );
    }

    function placeBidOnAuction(
        address collectionId,
        uint256 nftId,
        uint256 bidAmount,
        uint256 bidOptionIdx
    ) public payable whenNotPaused(12) {
        if (msg.value > 0) {
            addTokens(msg.sender, CurrencyTransfer.NATIVE, msg.value);
        }
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.placeBidOnAuction(
            userFloorAccounts,
            creditToken,
            underlying,
            nftId,
            bidAmount,
            bidOptionIdx
        );
    }

    function settleAuctions(
        address collectionId,
        uint256[] memory nftIds
    ) public whenNotPaused(13) {
        mustValidNftIds(nftIds);
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.settleAuctions(userFloorAccounts, underlying, nftIds);
    }

    function ownerInitRaffles(
        RaffleInitParam memory param
    ) public whenNotPaused(14) {
        mustValidNftIds(param.nftIds);

        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(param.collectionId);
        param.collectionId = underlying;

        collectionState.ownerInitRaffles(
            userFloorAccounts,
            collectionFees[underlying][param.ticketToken],
            param,
            creditToken
        );
    }

    function buyRaffleTickets(
        address collectionId,
        uint256 nftId,
        uint256 ticketCnt
    ) public payable whenNotPaused(15) {
        if (msg.value > 0) {
            addTokens(msg.sender, CurrencyTransfer.NATIVE, msg.value);
        }
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);

        collectionState.buyRaffleTickets(
            userFloorAccounts,
            creditToken,
            underlying,
            nftId,
            ticketCnt
        );
    }

    function settleRaffles(
        address collectionId,
        uint256[] memory nftIds
    ) public whenNotPaused(16) {
        mustValidNftIds(nftIds);
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);

        (bytes memory toSettleNftIds, uint256 len) = collectionState
            .prepareSettleRaffles(nftIds);
        if (len > 0) {
            uint256 requestId = COORDINATOR.requestRandomWords(
                keyHash,
                subId,
                3,
                800_000,
                uint32(len)
            );
            randomnessRequestToReceiver[requestId] = RandomRequestInfo({
                typ: 1,
                collection: underlying,
                data: toSettleNftIds
            });
        }
    }

    function _completeSettleRaffles(
        address collectionId,
        bytes memory data,
        uint256[] memory randoms
    ) private {
        CollectionState storage collection = collectionStates[collectionId];
        collection.settleRaffles(
            userFloorAccounts,
            collectionId,
            data,
            randoms
        );
    }

    function ownerInitPrivateOffers(
        PrivateOfferInitParam memory param
    ) public whenNotPaused(17) {
        mustValidNftIds(param.nftIds);

        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(param.collectionId);
        param.collectionId = underlying;
        collectionState.ownerInitPrivateOffers(
            userFloorAccounts,
            collectionFees[underlying][param.token],
            creditToken,
            param
        );
    }

    function modifyOffers(
        address collectionId,
        uint256[] memory nftIds,
        OfferOpType opTy,
        bytes calldata data
    ) public whenNotPaused(18) {
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.modifyOffers(
            userFloorAccounts,
            underlying,
            nftIds,
            opTy,
            data
        );
    }

    function buyerAcceptPrivateOffers(
        address collectionId,
        uint256[] memory nftIds,
        uint256 maxSafeboxExpiry
    ) public payable whenNotPaused(19) {
        mustValidNftIds(nftIds);
        if (msg.value > 0) {
            addTokens(msg.sender, CurrencyTransfer.NATIVE, msg.value);
        }
        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);
        collectionState.buyerAcceptPrivateOffers(
            userFloorAccounts,
            underlying,
            creditToken,
            nftIds,
            maxSafeboxExpiry
        );
    }

    function removeExpiredKeyAndRestoreCredit(
        address collectionId,
        uint256[] memory nftIds,
        address onBehalfOf,
        bool verifyLocking
    ) public whenNotPaused(20) returns (uint256) {
        mustValidNftIds(nftIds);

        (
            CollectionState storage collectionState,
            address underlying
        ) = useUnderlyingCollectionState(collectionId);

        return
            userFloorAccounts[onBehalfOf].removeExpiredKeysAndRestoreCredits(
                collectionState,
                underlying,
                nftIds,
                onBehalfOf,
                verifyLocking
            );
    }

    function recalculateAvailableCredit(
        address onBehalfOf
    ) public whenNotPaused(21) returns (uint256) {
        UserFloorAccount storage account = userFloorAccounts[onBehalfOf];

        uint256 minMaintCredit = account.recalculateMinMaintCredit(onBehalfOf);
        unchecked {
            /// when locking or extending, we ensure that `minMaintCredit` is less than `totalCredit`
            /// availableCredit = totalCredit - minMaintCredit
            return account.tokenBalance(creditToken) - minMaintCredit;
        }
    }

    function onERC721Received(
        address,
        /*operator*/
        address,
        /*from*/
        uint256,
        /*tokenId*/
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function useUnderlyingCollectionState(
        address collectionId
    ) private view returns (CollectionState storage, address) {
        address underlying = collectionProxy[collectionId];
        if (underlying == address(0)) {
            underlying = collectionId;
        }

        return (useCollectionState(underlying), underlying);
    }

    function useCollectionState(
        address collectionId
    ) private view returns (CollectionState storage) {
        CollectionState storage collection = collectionStates[collectionId];
        if (collection.nextKeyId == 0) {
            revert Errors.NftCollectionNotSupported();
        }
        return collection;
    }

    function mustSupportedToken(address token) private view {
        if (!supportedTokens[token]) revert Errors.TokenNotSupported();
    }

    function mustValidNftIds(uint256[] memory nftIds) private pure {
        if (nftIds.length == 0) revert Errors.InvalidParam();

        /// nftIds should be ordered and there should be no duplicate elements.
        for (uint256 i = 1; i < nftIds.length; ) {
            unchecked {
                if (nftIds[i] <= nftIds[i - 1]) {
                    revert Errors.InvalidParam();
                }
                ++i;
            }
        }
    }

    function mustValidExpiryTs(uint256 expiryTs) private view {
        if (expiryTs != 0 && expiryTs <= block.timestamp) {
            revert Errors.InvalidParam();
        }
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        RandomRequestInfo storage info = randomnessRequestToReceiver[requestId];

        _completeSettleRaffles(info.collection, info.data, randomWords);

        delete randomnessRequestToReceiver[requestId];
    }

    function collectionLockingAt(
        address collectionId,
        uint256 startTimestamp,
        uint256 endTimestamp
    ) public view returns (uint256[] memory) {
        return
            collectionStates[collectionId].getLockingBuckets(
                startTimestamp,
                endTimestamp
            );
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    function extsload(
        bytes32 startSlot,
        uint256 nSlots
    ) external view returns (bytes memory) {
        bytes memory value = new bytes(nSlots << 5);

        /// @solidity memory-safe-assembly
        assembly {
            for {
                let i := 0
            } lt(i, nSlots) {
                i := add(i, 1)
            } {
                mstore(add(value, shl(5, add(i, 1))), sload(add(startSlot, i)))
            }
        }

        return value;
    }

    receive() external payable {
        addTokens(msg.sender, CurrencyTransfer.NATIVE, msg.value);
    }
}
