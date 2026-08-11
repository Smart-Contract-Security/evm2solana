// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IArtvybeCollectionV2.sol";

/// @title IArtvybeCollectionV3
/// @notice V3 adds an on-chain Merkle allowlist with mutable root, owner toggle,
///         per-wallet mint cap, optional discounted price, and an optional
///         auto-flip timestamp that ends the allowlist phase and lets the
///         public mint() take over without a transaction.
///
///         All allowlist parameters are mutable post-deploy so creators can
///         react to demand mid-mint (e.g. flip to FCFS if hype is lower than
///         expected, swap the wallet list, end the allowlist early).
///
///         The legacy `mint()` function is preserved verbatim — it just
///         additionally reverts during the allowlist-only phase.
interface IArtvybeCollectionV3 is IArtvybeCollectionV2 {
    // -----------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------

    event AllowlistRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event AllowlistEnabledUpdated(bool enabled);
    event AllowlistConfigUpdated(
        uint256 walletLimit,
        uint256 mintPrice,
        uint256 allowlistEnd,
        uint256 publicStart
    );
    event AllowlistMint(
        address indexed minter,
        uint256 quantity,
        uint256 pricePerMint
    );
    event AllowlistEndedEarly(uint256 endedAt);

    // -----------------------------------------------------------------
    // Allowlist surface
    // -----------------------------------------------------------------

    /// @notice Mint while the allowlist phase is active, paying the (optionally
    ///         discounted) allowlist price. Reverts if the proof is invalid,
    ///         the per-wallet cap would be exceeded, the allowlist isn't
    ///         enabled, or the public phase has already started.
    function allowlistMint(uint256 quantity, bytes32[] calldata proof)
        external
        payable;

    /// @notice Update the Merkle root that authorises allowlist mints. Owner
    ///         can call this any time to swap the wallet list mid-mint.
    function setAllowlistRoot(bytes32 newRoot) external;

    /// @notice Toggle the allowlist on or off without touching the wallet list.
    ///         Disabling immediately opens the public mint regardless of timestamps.
    function setAllowlistEnabled(bool enabled) external;

    /// @notice Bulk-update the non-root allowlist parameters. All four
    ///         values are stored verbatim — there is no "pass 0 to keep
    ///         existing" sentinel. `walletLimit == 0` means "no per-wallet
    ///         cap", `mintPrice == 0` means "use the public mintPrice for
    ///         allowlist mints", `allowlistEnd == 0` means "no auto-flip
    ///         time", `publicStart == 0` means "public mint opens the
    ///         moment the allowlist phase ends". Callers that want to
    ///         preserve an existing field must read it first and pass it
    ///         back in.
    function setAllowlistConfig(
        uint256 walletLimit,
        uint256 mintPrice,
        uint256 allowlistEnd,
        uint256 publicStart
    ) external;

    /// @notice End the allowlist phase immediately. Equivalent to setting
    ///         `allowlistEnabled = false` plus `publicStart = block.timestamp`,
    ///         in one transaction.
    function endAllowlistEarly() external;

    // -----------------------------------------------------------------
    // Allowlist views
    // -----------------------------------------------------------------

    function allowlistMerkleRoot() external view returns (bytes32);

    function allowlistEnabled() external view returns (bool);

    function allowlistWalletLimit() external view returns (uint256);

    function allowlistMintPrice() external view returns (uint256);

    function allowlistEnd() external view returns (uint256);

    function publicStart() external view returns (uint256);

    function allowlistMinted(address wallet) external view returns (uint256);

    /// @notice Convenience helper — true while only `allowlistMint` is callable.
    function isAllowlistPhase() external view returns (bool);
}
