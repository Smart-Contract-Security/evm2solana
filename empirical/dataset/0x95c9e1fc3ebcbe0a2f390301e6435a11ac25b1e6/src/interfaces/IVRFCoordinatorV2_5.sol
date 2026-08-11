// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVRFCoordinatorV2_5
 * @dev Interface for Chainlink VRF v2.5
 */
interface IVRFCoordinatorV2_5 {
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId);

    function createSubscription() external returns (uint256 subId);

    function getSubscription(uint256 subId)
        external
        view
        returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address subOwner, address[] memory consumers);

    function addConsumer(uint256 subId, address consumer) external;

    function removeConsumer(uint256 subId, address consumer) external;

    function cancelSubscription(uint256 subId, address to) external;
}

/**
 * @dev VRF v2.5 client library
 */
library VRFV2PlusClient {
    bytes4 constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

    struct ExtraArgsV1 {
        bool nativePayment;
    }

    struct RandomWordsRequest {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bytes extraArgs;
    }

    function _argsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory bts) {
        bts = abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs);
    }
}
