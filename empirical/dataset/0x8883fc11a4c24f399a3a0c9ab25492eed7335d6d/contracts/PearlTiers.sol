// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Tier classification for Pearl Block Heroes
/// @notice Rules are PUBLIC and SIMPLE — easy for community to verify rarity.
library PearlTiers {

    enum Tier { Common, Rare, Epic, Legendary }

    /// @notice Returns the tier for a block number based on transparent rules.
    /// @dev Rules (checked in order — first match wins):
    ///   Legendary: 1, 100, 500, 1000, 2500, 5000, 8888
    ///   Epic:      palindromes (e.g., 11, 22, 101, 111, 121, 1001, 1111, 2002, ...)
    ///   Rare:      "all same digit" (e.g., 22, 333, 4444, ...) OR ends in "00" OR is power of 2
    ///   Common:    everything else
    function classify(uint256 n) internal pure returns (Tier) {
        if (_isLegendary(n))  return Tier.Legendary;
        if (_isPalindrome(n)) return Tier.Epic;
        if (_isRare(n))       return Tier.Rare;
        return Tier.Common;
    }

    function _isLegendary(uint256 n) private pure returns (bool) {
        return (n == 1 || n == 100 || n == 500 || n == 1000 ||
                n == 2500 || n == 5000 || n == 8888);
    }

    function _isPalindrome(uint256 n) private pure returns (bool) {
        if (n < 10) return false; // single digits don't count as palindromes here
        uint256 reversed = 0;
        uint256 original = n;
        uint256 temp = n;
        while (temp > 0) {
            reversed = reversed * 10 + (temp % 10);
            temp /= 10;
        }
        return original == reversed;
    }

    function _isRare(uint256 n) private pure returns (bool) {
        // ends in 00 (and > 0)
        if (n > 0 && n % 100 == 0) return true;
        // power of 2 (2, 4, 8, ..., 8192)
        if (n > 1 && (n & (n - 1)) == 0) return true;
        // all same digit (e.g., 22, 33, 333, 444, 555)
        if (_allSameDigit(n)) return true;
        return false;
    }

    function _allSameDigit(uint256 n) private pure returns (bool) {
        if (n < 10) return false;
        uint256 firstDigit = n % 10;
        uint256 temp = n / 10;
        while (temp > 0) {
            if (temp % 10 != firstDigit) return false;
            temp /= 10;
        }
        return true;
    }
}
