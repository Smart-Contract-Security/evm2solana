// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IEntropy} from "./IEntropy.sol";
import {IPackSale} from "../sale/IPackSale.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {Errors} from "../util/Errors.sol";

/// @title Entropy
/// @notice Chainlink VRF v2.5 adapter. PackSale calls `requestRandomness`,
/// the VRF coordinator calls `fulfillRandomWords` on this contract, and we
/// forward the verified words to PackSale's `onEntropy` callback.
///
/// The whitepaper §02 calls this module "Entropy" precisely because callers
/// don't care which provider produced the bits — only that they were
/// produced and are unbiased. PackSale never imports Chainlink directly.
contract Entropy is VRFConsumerBaseV2Plus, IEntropy {
    IProtocolRegistry public immutable registry;

    // ─── VRF subscription config (set by owner) ──────────────────────────
    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint32  public callbackGasLimit;
    uint16  public requestConfirmations;
    bool    public payInNative;     // true = pay coordinator in native ETH; false = LINK

    /// @dev requestId → packId mapping so we can route the callback back to
    /// the right pack.
    mapping(uint256 => uint256) public requestToPack;

    event RandomnessRequested(uint256 indexed requestId, uint256 indexed packId, address opener, uint32 numWords);
    event RandomnessFulfilled(uint256 indexed requestId, uint256 indexed packId);
    event VrfConfigUpdated();

    constructor(
        address vrfCoordinator,
        IProtocolRegistry _registry,
        address _initialOwner
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        // VRFConsumerBaseV2Plus already sets `s_vrfCoordinator` and inherits
        // a ConfirmedOwner. We override owner via `transferOwnership` if the
        // deployer != desired admin.
        registry = _registry;
        if (_initialOwner != address(0) && _initialOwner != msg.sender) {
            transferOwnership(_initialOwner);
        }
    }

    // ─── owner ───────────────────────────────────────────────────────────

    function setVrfConfig(
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32  _callbackGasLimit,
        uint16  _requestConfirmations,
        bool    _payInNative
    ) external onlyOwner {
        subscriptionId       = _subscriptionId;
        keyHash              = _keyHash;
        callbackGasLimit     = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        payInNative          = _payInNative;
        emit VrfConfigUpdated();
    }

    // ─── auth modifier ───────────────────────────────────────────────────

    modifier onlyPackSale() {
        if (msg.sender != registry.packSale()) revert Errors.NotAuthorized();
        _;
    }

    // ─── IEntropy ────────────────────────────────────────────────────────

    function requestRandomness(uint256 packId, address /*opener*/, uint32 numWords)
        external
        override
        onlyPackSale
        returns (uint256 requestId)
    {
        if (numWords == 0) revert Errors.ZeroAmount();

        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash:             keyHash,
            subId:               subscriptionId,
            requestConfirmations:requestConfirmations,
            callbackGasLimit:    callbackGasLimit,
            numWords:            numWords,
            extraArgs:           VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: payInNative})
            )
        });
        requestId = s_vrfCoordinator.requestRandomWords(req);
        requestToPack[requestId] = packId;
        emit RandomnessRequested(requestId, packId, msg.sender, numWords);
    }

    /// @dev Coordinator callback. Forwards the words to PackSale. We never
    /// keep the words around; PackSale consumes them inside its `onEntropy`
    /// handler and writes any derived state itself.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 packId = requestToPack[requestId];
        // packId 0 is reserved as "unknown request" — packs use 1-based ids.
        if (packId == 0) revert Errors.CallbackOutOfOrder();
        delete requestToPack[requestId];
        emit RandomnessFulfilled(requestId, packId);
        IPackSale(registry.packSale()).onEntropy(requestId, randomWords);
    }

    // ─── helpers ─────────────────────────────────────────────────────────

    /// @inheritdoc IEntropy
    function uniform(uint256[] memory words, uint256 wordIndex, uint256 modulus)
        external
        pure
        override
        returns (uint256)
    {
        require(modulus != 0, "uniform: zero modulus");
        return words[wordIndex] % modulus;
    }
}
