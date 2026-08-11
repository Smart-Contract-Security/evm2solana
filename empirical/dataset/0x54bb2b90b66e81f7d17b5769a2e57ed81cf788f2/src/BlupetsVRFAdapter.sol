// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IBlupetsRandomness} from "./IBlupetsRandomness.sol";

interface IBlupetsRandomnessReceiver {
    function rawFulfillRandomWords(uint256 requestId, uint256 randomWord) external;
}

contract BlupetsVRFAdapter is VRFConsumerBaseV2Plus, IBlupetsRandomness {
    uint32 public constant NUM_WORDS = 1;

    address public receiver;
    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    bool public nativePayment;
    mapping(uint256 => address) public requestReceiver;

    event ReceiverUpdated(address indexed receiver);
    event VRFConfigUpdated(
        uint256 indexed subscriptionId,
        bytes32 indexed keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        bool nativePayment
    );
    event RandomWordsRequested(uint256 indexed requestId, address indexed receiver);
    event RandomWordsFulfilled(uint256 indexed requestId, uint256 randomWord);
    event RandomWordsDeliveryFailed(uint256 indexed requestId, address indexed receiver);

    error OnlyReceiver();
    error InvalidReceiver();
    error InvalidDependency();
    error InvalidVRFConfig();

    constructor(
        address vrfCoordinator,
        address receiver_,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32 callbackGasLimit_,
        uint16 requestConfirmations_,
        bool nativePayment_
    ) VRFConsumerBaseV2Plus(_validateCoordinator(vrfCoordinator)) {
        _setReceiver(receiver_, true);
        _setConfig(subscriptionId_, keyHash_, callbackGasLimit_, requestConfirmations_, nativePayment_);
    }

    function requestRandomWords() external returns (uint256 requestId) {
        if (msg.sender != receiver) revert OnlyReceiver();

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
            })
        );

        requestReceiver[requestId] = msg.sender;
        emit RandomWordsRequested(requestId, msg.sender);
    }

    function setReceiver(address receiver_) external onlyOwner {
        _setReceiver(receiver_, false);
    }

    function setConfig(
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32 callbackGasLimit_,
        uint16 requestConfirmations_,
        bool nativePayment_
    ) external onlyOwner {
        _setConfig(subscriptionId_, keyHash_, callbackGasLimit_, requestConfirmations_, nativePayment_);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address receiver_ = requestReceiver[requestId];
        if (receiver_ == address(0)) {
            emit RandomWordsDeliveryFailed(requestId, address(0));
            return;
        }
        delete requestReceiver[requestId];

        uint256 randomWord = randomWords[0];
        try IBlupetsRandomnessReceiver(receiver_).rawFulfillRandomWords(requestId, randomWord) {
            emit RandomWordsFulfilled(requestId, randomWord);
        } catch {
            emit RandomWordsDeliveryFailed(requestId, receiver_);
        }
    }

    function _setReceiver(address receiver_, bool allowZero) internal {
        if (!allowZero && receiver_ == address(0)) revert InvalidReceiver();
        receiver = receiver_;
        emit ReceiverUpdated(receiver_);
    }

    function _validateCoordinator(address vrfCoordinator) private view returns (address) {
        if (vrfCoordinator == address(0) || vrfCoordinator.code.length == 0) revert InvalidDependency();
        return vrfCoordinator;
    }

    function _setConfig(
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32 callbackGasLimit_,
        uint16 requestConfirmations_,
        bool nativePayment_
    ) internal {
        if (subscriptionId_ == 0 || keyHash_ == bytes32(0) || callbackGasLimit_ == 0 || requestConfirmations_ == 0) {
            revert InvalidVRFConfig();
        }

        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        callbackGasLimit = callbackGasLimit_;
        requestConfirmations = requestConfirmations_;
        nativePayment = nativePayment_;

        emit VRFConfigUpdated(subscriptionId_, keyHash_, callbackGasLimit_, requestConfirmations_, nativePayment_);
    }
}
