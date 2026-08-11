// SPDX-License-Identifier: MIT OR Apache-2.0

library Message {
    uint64 private constant VERSION_OFFSET = 0;
    uint64 private constant NONCE_OFFSET = 1;
    uint64 private constant ORIGIN_OFFSET = 5;
    uint64 private constant SENDER_OFFSET = 9;
    uint64 private constant DESTINATION_OFFSET = 41;
    uint64 private constant RECIPIENT_OFFSET = 45;
    uint64 private constant BODY_OFFSET = 77;

    function formatMessage(
        uint8 _version,
        uint32 _nonce,
        uint32 _originDomain,
        bytes32 _sender,
        uint32 _destinationDomain,
        bytes32 _recipient,
        bytes calldata _messageBody
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                _version,
                _nonce,
                _originDomain,
                _sender,
                _destinationDomain,
                _recipient,
                _messageBody
            );
    }

    function id(bytes memory _message) internal pure returns (bytes32) {
        return keccak256(_message);
    }

    function version(bytes calldata _message) internal pure returns (uint8) {
        return uint8(_message[VERSION_OFFSET]);
    }

    function nonce(bytes calldata _message) internal pure returns (uint32) {
        uint32 result;
        for (uint64 i = 0; i < 4; i++) {
            result |= uint32(uint8(_message[NONCE_OFFSET + i])) << (i * 8);
        }
        return result;
    }

    function origin(bytes calldata _message) internal pure returns (uint32) {
        uint32 result;
        for (uint64 i = 0; i < 4; i++) {
            result |= uint32(uint8(_message[ORIGIN_OFFSET + i])) << (i * 8);
        }
        return result;
    }

    function sender(bytes calldata _message) internal pure returns (bytes32) {
        bytes32 result;
        for (uint64 i = 0; i < 32; i++) {
            result |= bytes32(uint256(uint8(_message[SENDER_OFFSET + i]))) << (i * 8);
        }
        return result;
    }

    function senderAddress(
        bytes calldata _message
    ) internal pure returns (address) {
        return address(uint160(uint256(sender(_message))));
    }

    function destination(
        bytes calldata _message
    ) internal pure returns (uint32) {
        uint32 result;
        for (uint64 i = 0; i < 4; i++) {
            result |= uint32(uint8(_message[DESTINATION_OFFSET + i])) << (i * 8);
        }
        return result;
    }

    function recipient(
        bytes calldata _message
    ) internal pure returns (bytes32) {
        bytes32 result;
        for (uint64 i = 0; i < 32; i++) {
            result |= bytes32(uint256(uint8(_message[RECIPIENT_OFFSET + i]))) << (i * 8);
        }
        return result;
    }

    function recipientAddress(
        bytes calldata _message
    ) internal pure returns (address) {
        return address(uint160(uint256(recipient(_message))));
    }

    function body(
        bytes calldata _message
    ) internal pure returns (bytes memory) {
        uint64 bodyLength = uint64(_message.length) - BODY_OFFSET;
        bytes memory result = new bytes(bodyLength);
        for (uint64 i = 0; i < bodyLength; i++) {
            result[i] = _message[BODY_OFFSET + i];
        }
        return result;
    }
}