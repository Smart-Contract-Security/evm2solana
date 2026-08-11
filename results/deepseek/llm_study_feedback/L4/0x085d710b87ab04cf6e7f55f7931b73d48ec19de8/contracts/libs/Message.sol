// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/**
 * @title Hyperlane Message Library
 * @notice Library for formatted messages used by Mailbox
 **/
library Message {
    uint256 private constant VERSION_OFFSET = 0;
    uint256 private constant NONCE_OFFSET = 1;
    uint256 private constant ORIGIN_OFFSET = 5;
    uint256 private constant SENDER_OFFSET = 9;
    uint256 private constant DESTINATION_OFFSET = 41;
    uint256 private constant RECIPIENT_OFFSET = 45;
    uint256 private constant BODY_OFFSET = 77;

    /**
     * @notice Returns formatted (packed) Hyperlane message with provided fields
     * @dev This function should only be used in memory message construction.
     * @param _version The version of the origin and destination Mailboxes
     * @param _nonce A nonce to uniquely identify the message on its origin chain
     * @param _originDomain Domain of origin chain
     * @param _sender Address of sender as bytes32
     * @param _destinationDomain Domain of destination chain
     * @param _recipient Address of recipient on destination chain as bytes32
     * @param _messageBody Raw bytes of message body
     * @return Formatted message
     */
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

    /**
     * @notice Returns the message ID.
     * @param _message ABI encoded Hyperlane message.
     * @return ID of `_message`
     */
    function id(bytes memory _message) internal pure returns (bytes32) {
        return keccak256(_message);
    }

    /**
     * @notice Returns the message version.
     * @param _message ABI encoded Hyperlane message.
     * @return Version of `_message`
     */
    function version(bytes calldata _message) internal pure returns (uint8) {
        return uint8(_message[VERSION_OFFSET]);
    }

    /**
     * @notice Returns the message nonce.
     * @param _message ABI encoded Hyperlane message.
     * @return Nonce of `_message`
     */
    function nonce(bytes calldata _message) internal pure returns (uint32) {
        uint32 val;
        for (uint256 i = 0; i < 4; i++) {
            val |= uint32(uint8(_message[NONCE_OFFSET + i])) << ((3 - i) * 8);
        }
        return val;
    }

    /**
     * @notice Returns the message origin domain.
     * @param _message ABI encoded Hyperlane message.
     * @return Origin domain of `_message`
     */
    function origin(bytes calldata _message) internal pure returns (uint32) {
        uint32 val;
        for (uint256 i = 0; i < 4; i++) {
            val |= uint32(uint8(_message[ORIGIN_OFFSET + i])) << ((3 - i) * 8);
        }
        return val;
    }

    /**
     * @notice Returns the message sender as bytes32.
     * @param _message ABI encoded Hyperlane message.
     * @return Sender of `_message` as bytes32
     */
    function sender(bytes calldata _message) internal pure returns (bytes32) {
        bytes32 val;
        for (uint256 i = 0; i < 32; i++) {
            val |= bytes32(uint256(uint8(_message[SENDER_OFFSET + i]))) << ((31 - i) * 8);
        }
        return val;
    }

    /**
     * @notice Returns the message sender as address.
     * @param _message ABI encoded Hyperlane message.
     * @return Sender of `_message` as address
     */
    function senderAddress(
        bytes calldata _message
    ) internal pure returns (address) {
        return address(uint160(uint256(sender(_message))));
    }

    /**
     * @notice Returns the message destination domain.
     * @param _message ABI encoded Hyperlane message.
     * @return Destination domain of `_message`
     */
    function destination(
        bytes calldata _message
    ) internal pure returns (uint32) {
        uint32 val;
        for (uint256 i = 0; i < 4; i++) {
            val |= uint32(uint8(_message[DESTINATION_OFFSET + i])) << ((3 - i) * 8);
        }
        return val;
    }

    /**
     * @notice Returns the message recipient as bytes32.
     * @param _message ABI encoded Hyperlane message.
     * @return Recipient of `_message` as bytes32
     */
    function recipient(
        bytes calldata _message
    ) internal pure returns (bytes32) {
        bytes32 val;
        for (uint256 i = 0; i < 32; i++) {
            val |= bytes32(uint256(uint8(_message[RECIPIENT_OFFSET + i]))) << ((31 - i) * 8);
        }
        return val;
    }

    /**
     * @notice Returns the message recipient as address.
     * @param _message ABI encoded Hyperlane message.
     * @return Recipient of `_message` as address
     */
    function recipientAddress(
        bytes calldata _message
    ) internal pure returns (address) {
        return address(uint160(uint256(recipient(_message))));
    }

    /**
     * @notice Returns the message body.
     * @param _message ABI encoded Hyperlane message.
     * @return Body of `_message`
     */
    function body(
        bytes calldata _message
    ) internal pure returns (bytes memory) {
        uint256 len = _message.length - BODY_OFFSET;
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = _message[BODY_OFFSET + i];
        }
        return result;
    }
}