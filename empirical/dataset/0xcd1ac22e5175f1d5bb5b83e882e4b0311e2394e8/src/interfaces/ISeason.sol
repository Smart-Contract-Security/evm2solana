// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISeason
/// @notice The only thing the immutable `SlopPacks` engine asks of a season:
///         render a pack's metadata. The engine stores which season minted each
///         pack (`seasonOf`) and routes `tokenURI` to it. Everything else about a
///         season (the open lifecycle, the draw, delivery, fees) is the season's
///         own concern and the engine never calls it.
interface ISeason {
    function packTokenURI(uint256 packTokenId) external view returns (string memory);
}
