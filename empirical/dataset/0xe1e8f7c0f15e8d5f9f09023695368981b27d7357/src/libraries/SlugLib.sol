// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library SlugLib {
    error EmptySlug();
    error SlugTooLong(uint256 max);
    error InvalidChar(uint256 index, bytes1 found);
    error LeadingOrTrailingDash();
    error DoubleDash(uint256 index);

    uint256 internal constant MAX_LEN = 32;

    /// @dev Enforces: only [a-z], [0-9], and '-', no leading/trailing '-', no "--"
    function assertValidSlug(string memory s) internal pure {
        bytes memory b = bytes(s);
        uint256 len = b.length;

        if (len == 0) revert EmptySlug();
        if (len > MAX_LEN) revert SlugTooLong(MAX_LEN);

        // no leading/trailing '-'
        if (b[0] == 0x2d || b[len - 1] == 0x2d) revert LeadingOrTrailingDash();

        bool prevDash = false;
        for (uint256 i = 0; i < len; ) {
            bytes1 c = b[i];

            // allow lowercase letters [a-z], digits [0-9], or hyphen '-'
            bool isLower = (c >= 0x61 && c <= 0x7a);
            bool isDigit = (c >= 0x30 && c <= 0x39);
            bool isDash  = (c == 0x2d);

            if (!isLower && !isDigit && !isDash) revert InvalidChar(i, c);

            if (isDash) {
                if (prevDash) revert DoubleDash(i); // prevent "--"
                prevDash = true;
            } else {
                prevDash = false;
            }

            unchecked { ++i; }
        }
    }

}
