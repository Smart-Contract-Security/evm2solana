// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IPackSale
/// @notice The PackSale interface Entropy calls back into on VRF fulfilment.
interface IPackSale {
    /// @notice Callback from Entropy. `requestId` came from a prior
    /// `requestRandomness` for this pack; `words` is the verified randomness.
    /// Reverts if `requestId` doesn't match a pending pack.
    function onEntropy(uint256 requestId, uint256[] calldata words) external;
}
