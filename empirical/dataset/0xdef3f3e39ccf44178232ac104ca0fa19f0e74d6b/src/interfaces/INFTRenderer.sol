// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

interface INFTRenderer {
    /// @notice Generate the full tokenURI for a receipt NFT
    /// @param receiptId The receipt/token ID
    /// @param system The ZuCitySystem contract address to read data from
    /// @return The full data URI string
    function tokenURI(uint256 receiptId, address system) external view returns (string memory);
}
