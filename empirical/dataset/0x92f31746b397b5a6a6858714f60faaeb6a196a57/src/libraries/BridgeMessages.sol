// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

/**
 * @title BridgeMessages
 * @notice Library for encoding and decoding bridge messages
 * @dev Defines message types and serialization for cross-chain communication
 */
library BridgeMessages {
    /// @notice Message type for bridging PT from EVM to Stellar
    uint8 public constant MSG_TYPE_BRIDGE_TO_STELLAR = 1;

    /// @notice Message type for bridging PT from Stellar back to EVM
    uint8 public constant MSG_TYPE_BRIDGE_FROM_STELLAR = 2;

    /// @notice Message type for bridging native Stellar PT to EVM (lock on Stellar, mint on EVM)
    uint8 public constant MSG_TYPE_STELLAR_PT_TO_EVM = 3;

    /// @notice Message type for bridging wrapped Stellar PT back from EVM (burn on EVM, unlock on Stellar)
    uint8 public constant MSG_TYPE_STELLAR_PT_FROM_EVM = 4;

    /// @notice Struct for bridge to Stellar message (type 1 — keeps sourceChainId)
    struct BridgeToStellarMsg {
        uint8 msgType;
        address ptAddress;          // PT address on source EVM chain
        uint256 amount;             // Amount to bridge
        uint32 sourceChainId;       // Source chain ID (Stellar needs this for origin keys)
        string stellarRecipient;    // Stellar recipient address
        uint256 maturity;           // PT maturity timestamp
        address underlying;         // Underlying asset address
        uint8 decimals;             // PT decimals
        string ptSymbol;            // PT symbol for identification
    }

    /// @notice Struct for bridge from Stellar message (type 2 — no targetChainId)
    struct BridgeFromStellarMsg {
        uint8 msgType;
        address ptAddress;          // Original PT address on EVM
        uint256 amount;             // Amount to unlock
        address evmRecipient;       // EVM recipient address
        bytes32 stellarTxHash;      // Stellar transaction hash for verification
    }

    function encodeBridgeToStellar(
        BridgeToStellarMsg memory msg_
    ) internal pure returns (bytes memory) {
        return abi.encode(
            msg_.msgType,
            msg_.ptAddress,
            msg_.amount,
            msg_.sourceChainId,
            msg_.stellarRecipient,
            msg_.maturity,
            msg_.underlying,
            msg_.decimals,
            msg_.ptSymbol
        );
    }

    function decodeBridgeToStellar(
        bytes memory data
    ) internal pure returns (BridgeToStellarMsg memory msg_) {
        (
            msg_.msgType,
            msg_.ptAddress,
            msg_.amount,
            msg_.sourceChainId,
            msg_.stellarRecipient,
            msg_.maturity,
            msg_.underlying,
            msg_.decimals,
            msg_.ptSymbol
        ) = abi.decode(
            data,
            (uint8, address, uint256, uint32, string, uint256, address, uint8, string)
        );
    }

    function encodeBridgeFromStellar(
        BridgeFromStellarMsg memory msg_
    ) internal pure returns (bytes memory) {
        return abi.encode(
            msg_.msgType,
            msg_.ptAddress,
            msg_.amount,
            msg_.evmRecipient,
            msg_.stellarTxHash
        );
    }

    function decodeBridgeFromStellar(
        bytes memory data
    ) internal pure returns (BridgeFromStellarMsg memory msg_) {
        (
            msg_.msgType,
            msg_.ptAddress,
            msg_.amount,
            msg_.evmRecipient,
            msg_.stellarTxHash
        ) = abi.decode(
            data,
            (uint8, address, uint256, address, bytes32)
        );
    }

    /// @notice Struct for native Stellar PT to EVM message (fixed 288-byte payload from Stellar)
    struct StellarPtToEvmMsg {
        uint8 msgType;
        string stellarPtAddress;    // 56-char Stellar strkey (C...)
        uint256 amount;
        address evmRecipient;
        uint64 maturity;
        uint8 decimals;
        bytes32 stellarTxHash;      // Message nonce / tx hash
        bytes32 ptSymbol;           // First 32 bytes of symbol, zero-padded
    }

    /// @notice Struct for burning wrapped Stellar PT on EVM to unlock on Stellar (type 4 — no sourceChainId)
    struct StellarPtFromEvmMsg {
        uint8 msgType;
        uint256 amount;
        string stellarPtAddress;    // 56-char Stellar strkey (C...)
        string stellarRecipient;    // Stellar address (56-char strkey, G... or C...)
    }

    /**
     * @notice Decodes a native Stellar PT to EVM message (288-byte fixed-slot payload)
     * @param data The 288-byte payload from Stellar (9 slots)
     * @return msg_ The decoded message
     */
    function decodeStellarPtToEvm(
        bytes calldata data
    ) internal pure returns (StellarPtToEvmMsg memory msg_) {
        require(data.length >= 288, "Invalid payload length");

        // Slot 0: msgType (byte 31)
        msg_.msgType = uint8(data[31]);
        // Slot 1-2: stellarPtAddress strkey (56 bytes at 32..87, zero-padded to 64)
        bytes memory strkey = new bytes(56);
        for (uint256 i = 0; i < 56; i++) {
            strkey[i] = data[32 + i];
        }
        msg_.stellarPtAddress = string(strkey);
        // Slot 3: amount (i128 big-endian in bytes 112..127)
        msg_.amount = uint256(uint128(bytes16(data[112:128])));
        // Slot 4: evmRecipient (right-aligned 20 bytes)
        msg_.evmRecipient = address(uint160(bytes20(data[140:160])));
        // Slot 5: maturity (bytes 184..191)
        msg_.maturity = uint64(bytes8(data[184:192]));
        // Slot 6: decimals (byte 223)
        msg_.decimals = uint8(data[223]);
        // Slot 7: tx hash
        msg_.stellarTxHash = bytes32(data[224:256]);
        // Slot 8: symbol
        msg_.ptSymbol = bytes32(data[256:288]);
    }

    function encodeStellarPtFromEvm(
        StellarPtFromEvmMsg memory msg_
    ) internal pure returns (bytes memory) {
        return abi.encode(
            msg_.msgType,
            msg_.amount,
            msg_.stellarPtAddress,
            msg_.stellarRecipient
        );
    }

    function getMessageType(bytes memory data) internal pure returns (uint8) {
        return abi.decode(data, (uint8));
    }
}
