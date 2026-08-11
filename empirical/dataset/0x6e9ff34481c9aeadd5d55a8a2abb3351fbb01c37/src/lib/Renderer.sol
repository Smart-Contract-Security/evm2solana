// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "./Types.sol";
import {SVG} from "./SVG.sol";
import {Figure} from "./Figure.sol";
import {TierAccents} from "./TierAccents.sol";

/// @title Renderer — composes the full woodcut SVG from token traits
/// @notice All pure functions. No storage. ~100% onchain SVG output.
library Renderer {

    /// @notice Render the full SVG for a token.
    function renderSVG(uint256 tokenId, Types.TokenData memory d)
        public
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(
            SVG.header(),
            SVG.background(d.background),
            SVG.grain(),
            SVG.frame(d.tier),
            SVG.topSigil(d.topSigil, d.tier),
            SVG.latinDesignation(d.tier),
            TierAccents.backdrop(d.tier),
            Figure.render(d.hoodShape, d.faceInside, d.posture, d.cloakDetail),
            Figure.obolInPosition(d.obolPosition),
            SVG.coinMark(d.coinMark, d.tier),
            SVG.riverWaves(d.tier),
            TierAccents.render(d.tier),
            SVG.tierMark(d.tier),
            SVG.signaturePlate(tokenId, d.tier),
            SVG.footer()
        ));
    }
}
