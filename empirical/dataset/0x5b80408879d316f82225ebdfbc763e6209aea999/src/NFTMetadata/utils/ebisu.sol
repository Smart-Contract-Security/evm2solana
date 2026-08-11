//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./SVG.sol";
import "./FixedAssets.sol";

library ebisuSVG {
    string constant A = "#EE4F9C";
    string constant B = "#FCF7F2";
    string constant C = "#FFF172";
    string constant D = "#AF96FB";
    string constant E = "#FC7339";
    string constant F = "#BEFF6C";
    string constant G = "#EFEFEF";
    string constant H = "#49DBC8";
    string constant I = "#F5D93A";

    function _hero(uint256 _troveId, FixedAssetReader _assetReader) internal view returns (string memory) {
        uint256 variant = _troveId % 9;
        string memory color;

        if (variant == 0) {
            color = A;
        } else if (variant == 1) {
            color = B;
        } else if (variant == 2) {
            color = C;
        } else if (variant == 3) {
            color = D;
        } else if (variant == 4) {
            color = E;
        } else if (variant == 5) {
            color = F;
        } else if (variant == 6) {
            color = G;
        } else if (variant == 7) {
            color = H;
        } else {
            color = I;
        }

        return string.concat(
            svg.rect(
                string.concat(
                    svg.prop("x", "16"),
                    svg.prop("y", "55"),
                    svg.prop("width", "268"),
                    svg.prop("height", "268"),
                    svg.prop("fill", color)
                )
            ),
            svg.el(
                "image",
                string.concat(
                    svg.prop("x", "16"),
                    svg.prop("y", "63"),
                    svg.prop("width", "268"),
                    svg.prop("height", "268"),
                    svg.prop(
                        "href",
                        string.concat(
                            "data:image/svg+xml;base64,", _assetReader.readAsset(bytes4(keccak256(bytes("HERO"))))
                        )
                    )
                )
            )
        );
    }
}
