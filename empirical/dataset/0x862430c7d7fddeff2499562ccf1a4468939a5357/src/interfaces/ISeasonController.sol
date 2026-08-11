// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISeasonController
/// @notice The swappable logic half of a season. Users call it directly to mint,
///         open, settle and deliver packs; it drives the season's durable state
///         and renders pack art. The engine does NOT call the controller — it only
///         knows the state (the registered minter). This interface is the small
///         surface the state needs from its controller:
///           * `state()` — the durable store this controller is bound to, checked
///             by the state's `setController` so a controller can't be activated
///             against a store it wasn't built for.
///           * `packTokenURI` — the state forwards the engine's `tokenURI` here, so
///             art lives with the (swappable) logic.
interface ISeasonController {
    function state() external view returns (address);

    function packTokenURI(uint256 packTokenId) external view returns (string memory);
}
