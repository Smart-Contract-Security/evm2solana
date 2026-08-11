// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

/**
 * @title StellarAddressValidator
 * @notice Library for validating Stellar addresses
 * @dev Stellar addresses are base32-encoded strings starting with 'G' (public key) or 'C' (contract)
 */
library StellarAddressValidator {
    /// @notice The length of a valid Stellar address (56 characters)
    uint256 public constant STELLAR_ADDRESS_LENGTH = 56;

    /**
     * @notice Validates a Stellar address
     * @param stellarAddress The Stellar address to validate
     * @return True if the address is valid, false otherwise
     */
    function isValidStellarAddress(string memory stellarAddress) internal pure returns (bool) {
        bytes memory addrBytes = bytes(stellarAddress);

        // Check length
        if (addrBytes.length != STELLAR_ADDRESS_LENGTH) {
            return false;
        }

        // Check first character - must be 'G' (public key) or 'C' (contract)
        bytes1 firstChar = addrBytes[0];
        if (firstChar != 'G' && firstChar != 'C') {
            return false;
        }

        // Validate all characters are valid base32
        for (uint256 i = 0; i < addrBytes.length; i++) {
            if (!isValidBase32Char(addrBytes[i])) {
                return false;
            }
        }

        // Note: Full checksum validation would require implementing CRC16-CCITT
        // which is gas-expensive. For production, consider:
        // 1. Off-chain validation before transaction
        // 2. Using a precompile if available
        // 3. Accept the basic validation above

        return true;
    }

    /**
     * @notice Checks if a character is valid in base32 encoding
     * @param c The character to check
     * @return True if valid base32 character
     */
    function isValidBase32Char(bytes1 c) internal pure returns (bool) {
        // Valid characters: A-Z (65-90) and 2-7 (50-55)
        uint8 charCode = uint8(c);

        // A-Z
        if (charCode >= 65 && charCode <= 90) {
            return true;
        }

        // 2-7
        if (charCode >= 50 && charCode <= 55) {
            return true;
        }

        return false;
    }
}
