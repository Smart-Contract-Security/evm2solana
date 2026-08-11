// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FrozenIndices} from "../OCCV2TraitTypes.sol";

/// @title IOCCV2MetadataGenerator — Interface for on-chain metadata generation
/// @notice The OCC V2 generator accepts the dual seed + frozen indices so the
///         displayed traits, mood, and clothing color all honor the freeze /
///         reshuffle rules without the NFT having to pre-resolve them.
///
///         The last four parameters surface the owner-mutable extensions
///         (background re-roll + trait freeze + transfer count) into the
///         metadata so marketplaces can render them as attributes:
///           • `transferCount`  — live count; always the real value (NOT the
///             snapshot taken at freeze time), so the Transfer Count attribute
///             keeps incrementing even while the visual traits stay locked.
///           • `traitsLocked`   — current Locked attribute value.
///           • `backgroundReshuffleEnabled` + `backgroundRerollNonce` —
///             drive the background color derivation (default Light Grey
///             until the first reroll, then color is derived from
///             `keccak(reshSeed, "bg", rerollNonce) % 9`).
interface IOCCV2MetadataGenerator {
    function generateMetadata(
        uint256 tokenId,
        uint256 permSeed,
        uint256 reshSeed,
        uint256 reshSeedAtMint,
        FrozenIndices calldata frozen,
        uint16 eyesThreshold,
        uint16 eyebrowsThreshold,
        uint16 mouthThreshold,
        uint16 clothingThreshold,
        uint16 accessoryIIThreshold,
        uint32 transferCount,
        bool traitsLocked,
        bool backgroundReshuffleEnabled,
        uint32 backgroundRerollNonce
    ) external view returns (string memory);
}
