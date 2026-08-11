// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibString} from "solady/src/utils/LibString.sol";

library DaemonAnimationData {
    using LibString for uint256;

    string private constant BG_KEY_TIMES =
        "0;0.0513;0.1026;0.1538;0.2051;0.2564;0.2714;0.2821;0.2949;0.3205;0.3718;0.4231;0.4744;0.5256;0.5769;0.6026;0.6175;0.6282;0.641;0.6923;0.7436;0.7949;0.8462;0.8974;0.9487;1";
    string private constant ANIM_DUR = "4.68s";

    string private constant STATE_1_OPACITY = "0;1;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0;0;0;0;1;0;0;0;0";
    string private constant STATE_1_EVEN =
        "M1 1h2v1H1zM17 1h2v1H17zM6 3h1v1H6zM11 3h1v1H11zM14 3h1v1H14zM22 3h1v1H22zM1 5h2v1H1zM5 5h1v1H5zM7 5h1v1H7zM9 5h1v1H9zM15 5h1v1H15zM18 5h1v1H18zM6 7h1v1H6zM11 7h1v1H11zM22 7h1v1H22zM1 9h2v1H1zM7 9h1v1H7zM14 9h2v1H14zM17 9h2v1H17zM5 11h1v1H5zM11 11h1v1H11zM22 11h1v1H22zM1 13h2v1H1zM7 13h1v1H7zM14 13h2v1H14zM17 13h2v1H17zM6 15h1v1H6zM11 15h1v1H11zM22 15h1v1H22zM1 17h2v1H1zM7 17h1v1H7zM14 17h2v1H14zM17 17h2v1H17zM6 19h1v1H6zM11 19h1v1H11zM22 19h1v1H22zM1 21h2v1H1zM6 21h2v1H6zM17 21h2v1H17zM14 23h1v1H14zM22 23h1v1H22z";
    string private constant STATE_1_ODD =
        "M3 0h1v1H3zM11 0h1v1H11zM19 0h1v1H19zM3 4h1v1H3zM6 4h1v1H6zM16 4h1v1H16zM19 4h1v1H19zM3 8h1v1H3zM8 8h1v1H8zM16 8h1v1H16zM19 8h1v1H19zM3 12h1v1H3zM6 12h1v1H6zM8 12h1v1H8zM16 12h1v1H16zM19 12h1v1H19zM3 16h1v1H3zM8 16h1v1H8zM16 16h1v1H16zM19 16h1v1H19zM3 20h1v1H3zM8 20h1v1H8zM19 20h1v1H19z";
    string private constant STATE_2_OPACITY = "0;0;0;1;0;0;0;0;0;1;0;0;0;1;0;0;0;0;0;1;0;0;0;1;0;0";
    string private constant STATE_2_EVEN =
        "M0 1h1v1H0zM8 1h1v1H8zM13 1h1v1H13zM16 1h1v1H16zM3 3h2v1H3zM9 3h1v1H9zM17 3h1v1H17zM19 3h2v1H19zM0 5h1v1H0zM13 5h1v1H13zM3 7h2v1H3zM8 7h2v1H8zM16 7h1v1H16zM19 7h2v1H19zM0 9h1v1H0zM13 9h1v1H13zM3 11h2v1H3zM6 11h4v1H6zM16 11h2v1H16zM19 11h2v1H19zM0 13h1v1H0zM13 13h1v1H13zM3 15h2v1H3zM7 15h3v1H7zM16 15h2v1H16zM19 15h2v1H19zM0 17h1v1H0zM13 17h1v1H13zM3 19h2v1H3zM8 19h2v1H8zM19 19h2v1H19zM0 21h1v1H0zM16 21h1v1H16zM3 23h1v1H3zM8 23h2v1H8zM11 23h2v1H11zM19 23h2v1H19z";
    string private constant STATE_2_ODD =
        "M5 2h1v1H5zM13 2h1v1H13zM21 2h1v1H21zM10 6h1v1H10zM21 6h1v1H21zM10 10h1v1H10zM21 10h1v1H21zM5 14h1v1H5zM10 14h1v1H10zM21 14h1v1H21zM5 18h1v1H5zM10 18h1v1H10zM21 18h1v1H21zM13 22h1v1H13zM21 22h1v1H21z";
    string private constant STATE_3_OPACITY = "0;0;0;0;0;1;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0";
    string private constant STATE_3_EVEN =
        "M1 1h2v1H1zM8 1h1v1H8zM14 1h1v1H14zM17 1h2v1H17zM6 3h1v1H6zM8 3h1v1H8zM11 3h1v1H11zM14 3h1v1H14zM22 3h1v1H22zM1 5h2v1H1zM5 5h1v1H5zM7 5h1v1H7zM9 5h1v1H9zM15 5h1v1H15zM18 5h1v1H18zM6 7h1v1H6zM11 7h1v1H11zM22 7h1v1H22zM1 9h2v1H1zM7 9h1v1H7zM14 9h2v1H14zM17 9h2v1H17zM5 11h1v1H5zM11 11h1v1H11zM22 11h1v1H22zM1 13h2v1H1zM7 13h1v1H7zM14 13h2v1H14zM17 13h2v1H17zM6 15h1v1H6zM11 15h1v1H11zM22 15h1v1H22zM1 17h2v1H1zM7 17h1v1H7zM14 17h2v1H14zM17 17h2v1H17zM6 19h1v1H6zM11 19h1v1H11zM22 19h1v1H22zM1 21h2v1H1zM6 21h2v1H6zM17 21h2v1H17zM14 23h1v1H14zM22 23h1v1H22z";
    string private constant STATE_3_ODD =
        "M3 0h1v1H3zM11 0h1v1H11zM19 0h1v1H19zM3 4h1v1H3zM6 4h1v1H6zM16 4h1v1H16zM19 4h1v1H19zM3 8h1v1H3zM8 8h1v1H8zM16 8h1v1H16zM19 8h1v1H19zM3 12h1v1H3zM6 12h1v1H6zM8 12h1v1H8zM16 12h1v1H16zM19 12h1v1H19zM3 16h1v1H3zM8 16h1v1H8zM16 16h1v1H16zM19 16h1v1H19zM3 20h1v1H3zM8 20h1v1H8zM19 20h1v1H19z";
    string private constant STATE_4_OPACITY = "0;0;0;0;0;0;1;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0;0;0;0";
    string private constant STATE_4_EVEN =
        "M1 1h2v1H1zM8 1h1v1H8zM14 1h2v1H14zM17 1h2v1H17zM6 3h1v1H6zM11 3h1v1H11zM14 3h1v1H14zM22 3h1v1H22zM1 5h2v1H1zM5 5h1v1H5zM7 5h1v1H7zM9 5h1v1H9zM15 5h1v1H15zM18 5h1v1H18zM6 7h1v1H6zM11 7h1v1H11zM22 7h1v1H22zM1 9h2v1H1zM7 9h1v1H7zM14 9h2v1H14zM17 9h2v1H17zM5 11h1v1H5zM11 11h1v1H11zM22 11h1v1H22zM1 13h2v1H1zM7 13h1v1H7zM14 13h2v1H14zM17 13h2v1H17zM6 15h1v1H6zM11 15h1v1H11zM22 15h1v1H22zM1 17h2v1H1zM7 17h1v1H7zM14 17h2v1H14zM17 17h2v1H17zM6 19h1v1H6zM11 19h1v1H11zM22 19h1v1H22zM1 21h2v1H1zM6 21h2v1H6zM17 21h2v1H17zM14 23h1v1H14zM22 23h1v1H22z";
    string private constant STATE_4_ODD =
        "M3 0h1v1H3zM11 0h1v1H11zM19 0h1v1H19zM3 4h1v1H3zM6 4h1v1H6zM16 4h1v1H16zM19 4h1v1H19zM3 8h1v1H3zM8 8h1v1H8zM16 8h1v1H16zM19 8h1v1H19zM3 12h1v1H3zM6 12h1v1H6zM8 12h1v1H8zM16 12h1v1H16zM19 12h1v1H19zM3 16h1v1H3zM8 16h1v1H8zM16 16h1v1H16zM19 16h1v1H19zM3 20h1v1H3zM8 20h1v1H8zM19 20h1v1H19z";
    string private constant STATE_5_OPACITY = "0;0;0;0;0;0;0;1;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0";
    string private constant STATE_5_EVEN = "M8 1h1v1H8zM15 1h1v1H15z";
    string private constant STATE_6_OPACITY = "0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0;0;0;0;0";
    string private constant STATE_6_EVEN = "M8 1h1v1H8zM14 1h1v1H14zM8 3h1v1H8zM14 3h1v1H14z";
    string private constant STATE_7_OPACITY = "0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0;0;0";
    string private constant STATE_7_EVEN =
        "M1 1h2v1H1zM8 1h1v1H8zM15 1h1v1H15zM17 1h2v1H17zM6 3h1v1H6zM11 3h1v1H11zM14 3h1v1H14zM22 3h1v1H22zM1 5h2v1H1zM5 5h1v1H5zM7 5h1v1H7zM9 5h1v1H9zM15 5h1v1H15zM18 5h1v1H18zM6 7h1v1H6zM11 7h1v1H11zM22 7h1v1H22zM1 9h2v1H1zM7 9h1v1H7zM14 9h2v1H14zM17 9h2v1H17zM5 11h1v1H5zM11 11h1v1H11zM22 11h1v1H22zM1 13h2v1H1zM7 13h1v1H7zM14 13h2v1H14zM17 13h2v1H17zM6 15h1v1H6zM11 15h1v1H11zM22 15h1v1H22zM1 17h2v1H1zM7 17h1v1H7zM14 17h2v1H14zM17 17h2v1H17zM6 19h1v1H6zM11 19h1v1H11zM22 19h1v1H22zM1 21h2v1H1zM6 21h2v1H6zM17 21h2v1H17zM14 23h1v1H14zM22 23h1v1H22z";
    string private constant STATE_7_ODD =
        "M3 0h1v1H3zM11 0h1v1H11zM19 0h1v1H19zM3 4h1v1H3zM6 4h1v1H6zM16 4h1v1H16zM19 4h1v1H19zM3 8h1v1H3zM8 8h1v1H8zM16 8h1v1H16zM19 8h1v1H19zM3 12h1v1H3zM6 12h1v1H6zM8 12h1v1H8zM16 12h1v1H16zM19 12h1v1H19zM3 16h1v1H3zM8 16h1v1H8zM16 16h1v1H16zM19 16h1v1H19zM3 20h1v1H3zM8 20h1v1H8zM19 20h1v1H19z";

    function crtBackground(uint8 id) public pure returns (string memory svg) {
        (string memory oddRow, string memory evenRow) = _crtBackgroundColors(id);
        svg = _baseFrame(oddRow, evenRow);
        return string.concat(svg, _stateFrames(oddRow, evenRow));
    }

    function _baseFrame(string memory oddRow, string memory evenRow) private pure returns (string memory svg) {
        svg = "<g>";
        for (uint8 y = 0; y < 24; ++y) {
            svg = string.concat(
                svg,
                "<rect x='0' y='",
                uint256(y).toString(),
                "' width='24' height='1' fill='",
                y % 2 == 0 ? evenRow : oddRow,
                "'/>"
            );
        }
        return string.concat(svg, "</g>");
    }

    function _stateFrames(string memory oddRow, string memory evenRow) private pure returns (string memory) {
        return string.concat(
            _state(STATE_1_OPACITY, string.concat(_path(STATE_1_EVEN, evenRow), _path(STATE_1_ODD, oddRow))),
            _state(STATE_2_OPACITY, string.concat(_path(STATE_2_EVEN, evenRow), _path(STATE_2_ODD, oddRow))),
            _state(STATE_3_OPACITY, string.concat(_path(STATE_3_EVEN, evenRow), _path(STATE_3_ODD, oddRow))),
            _state(STATE_4_OPACITY, string.concat(_path(STATE_4_EVEN, evenRow), _path(STATE_4_ODD, oddRow))),
            _state(STATE_5_OPACITY, _path(STATE_5_EVEN, evenRow)),
            _state(STATE_6_OPACITY, _path(STATE_6_EVEN, evenRow)),
            _state(STATE_7_OPACITY, string.concat(_path(STATE_7_EVEN, evenRow), _path(STATE_7_ODD, oddRow)))
        );
    }

    function _state(string memory opacityValues, string memory content) private pure returns (string memory) {
        return string.concat(
            "<g opacity='0'><animate attributeName='opacity' calcMode='discrete' values='",
            opacityValues,
            "' keyTimes='",
            BG_KEY_TIMES,
            "' dur='",
            ANIM_DUR,
            "' repeatCount='indefinite'/>",
            content,
            "</g>"
        );
    }

    function _path(string memory d, string memory color) private pure returns (string memory) {
        return string.concat("<path d='", d, "' fill='", color, "'/>");
    }

    function _crtBackgroundColors(uint8 id) private pure returns (string memory oddRow, string memory evenRow) {
        if (id == 0) return ("#000000", "#060606");
        if (id == 1) return ("#292929", "#2c2c2c");
        if (id == 2) return ("#4d4d4d", "#525252");
        if (id == 3) return ("#d3d3d3", "#d6d6d6");
        revert("BAD_BACKGROUND_ID");
    }
}
