// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IEntropy
/// @notice Interface PackSale uses to request randomness; the underlying
/// VRF provider is hidden behind this so we can swap Chainlink → Pyth →
/// custom mock without touching PackSale.
interface IEntropy {
    /// @notice Request `numWords` of randomness for a given pack open.
    /// @param packId   the pack being opened
    /// @param opener   the address that owns the pack
    /// @param numWords how many 256-bit random words to return
    /// @return requestId the underlying provider's request id
    function requestRandomness(uint256 packId, address opener, uint32 numWords)
        external
        returns (uint256 requestId);

    /// @dev Convenience helper for the callback: slice `wordIndex` from
    /// `words` and reduce to a uniform integer in [0, modulus).
    function uniform(uint256[] memory words, uint256 wordIndex, uint256 modulus)
        external
        pure
        returns (uint256);
}
