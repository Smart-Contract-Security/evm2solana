// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {DynamicBufferLib} from "solady/utils/DynamicBufferLib.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

import {IAbnormies, AbnormieState, Cascade} from "./interfaces/IAbnormies.sol";
import {INormies} from "./interfaces/INormies.sol";

contract AbnormiesRenderer {
    using DynamicBufferLib for DynamicBufferLib.DynamicBuffer;

    uint256 public constant CANVAS_SIZE = 1600;
    uint256 public constant CANVAS_WIDTH = 40;

    bytes6 internal constant COLOR_SKY = "e3e5e4";
    bytes6 internal constant COLOR_CIRRUS = "b0b1b0";
    bytes6 internal constant COLOR_ALTOCUMULUS = "7c7d7e";
    bytes6 internal constant COLOR_NIMBOSTRATUS = "48494b";

    address public immutable abnormiesContract;
    address public immutable normiesContract;

    error TokenDoesNotExist(uint256 tokenId);

    constructor(address abnormiesContract_, address normiesContract_) {
        abnormiesContract = abnormiesContract_;
        normiesContract = normiesContract_;
    }

    // ---------------------------------------------------------------------
    // Public entry points
    // ---------------------------------------------------------------------

    function tokenURI(uint256 abnormieId) external view returns (string memory) {
        (
            uint8[1600] memory canvas,
            uint16 lightningCount,
            uint16 thunderCount,
            bool inverted,
            uint16 effectiveCirrus,
            bool effectiveCustomized,
            bool effectiveDead
        ) = _render(abnormieId);

        AbnormieState memory s = IAbnormies(abnormiesContract).getAbnormieState(abnormieId);
        (,,,, bool awakened,) = IAbnormies(abnormiesContract).getSeedState(s.seedNormieId);

        uint64 effectiveDeadAtBlock =
            s.staticAt == 0 ? IAbnormies(abnormiesContract).seedDeadAtBlock(s.seedNormieId) : s.seedDeadAtBlockAtFreeze;

        (bytes memory svg, uint16 cVis, uint16 aVis, uint16 nVis) = _renderSvg(canvas);

        bytes memory json = _buildJson(
            UriData({
                abnormieId: abnormieId,
                s: s,
                cirrusN: effectiveCirrus,
                customized: effectiveCustomized,
                burned: effectiveDead,
                awakened: awakened,
                inverted: inverted,
                lightningCount: lightningCount,
                thunderCount: thunderCount,
                cirrusVisible: cVis,
                altocumulusVisible: aVis,
                nimbostratusVisible: nVis,
                nonSky: cVis + aVis + nVis,
                deadAtBlock: effectiveDeadAtBlock,
                svg: svg
            })
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function computeCanvas(uint256 abnormieId) external view returns (uint8[1600] memory canvas) {
        (canvas,,,,,,) = _render(abnormieId);
    }

    // ---------------------------------------------------------------------
    // Internal rendering
    // ---------------------------------------------------------------------

    struct UriData {
        uint256 abnormieId;
        AbnormieState s;
        uint16 cirrusN;
        bool customized;
        bool burned;
        bool awakened;
        bool inverted;
        uint16 lightningCount;
        uint16 thunderCount;
        uint16 cirrusVisible;
        uint16 altocumulusVisible;
        uint16 nimbostratusVisible;
        uint16 nonSky;
        uint64 deadAtBlock;
        bytes svg;
    }

    function _render(uint256 abnormieId)
        internal
        view
        returns (
            uint8[1600] memory canvas,
            uint16 lightningCount,
            uint16 thunderCount,
            bool inverted,
            uint16 effectiveCirrus,
            bool effectiveCustomized,
            bool effectiveDead
        )
    {
        AbnormieState memory s = IAbnormies(abnormiesContract).getAbnormieState(abnormieId);

        if (s.seedNormieId == 0 && s.pairedAtCascadeIndex == 0) {
            try IAbnormies(abnormiesContract).ownerOf(abnormieId) returns (
                address
            ) {
            // Token exists; proceed.
            }
            catch {
                revert TokenDoesNotExist(abnormieId);
            }
        }

        (, uint16 liveCirrus, bool liveCustomized, bool liveBurned, bool awakened,) =
            IAbnormies(abnormiesContract).getSeedState(s.seedNormieId);
        Cascade[] memory cascades = IAbnormies(abnormiesContract).getAllCascades();

        // Static Abnormies render against the snapshot fields captured at freeze time. Active
        // Abnormies render against live seed state.
        if (s.staticAt == 0) {
            effectiveCirrus = liveCirrus;
            effectiveCustomized = liveCustomized;
            effectiveDead = liveBurned;
        } else {
            effectiveCirrus = s.cirrusCountAtFreeze;
            effectiveCustomized = s.seedCustomizedAtFreeze;
            effectiveDead = s.seedDeadAtFreeze;
        }

        _paintCirrus(canvas, s.seedNormieId, effectiveCirrus);
        if (effectiveCustomized) _paintSourceNimbostratus(canvas, s.seedNormieId);
        (lightningCount, thunderCount) = _paintCascades(canvas, abnormieId, s, cascades);

        if (awakened && _ownersMatch(s.seedNormieId, abnormieId)) {
            _invertCanvas(canvas);
            inverted = true;
        }
    }

    function _paintCirrus(uint8[1600] memory canvas, uint16 seedNormieId, uint16 cirrusN) internal pure {
        for (uint256 e = 0; e < cirrusN;) {
            for (uint256 j = 0; j < 2;) {
                uint16 pos = uint16(uint256(keccak256(abi.encode(seedNormieId, "cirrus", e, j))) % CANVAS_SIZE);
                _paint(canvas, pos, 1);
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++e;
            }
        }
    }

    function _paintSourceNimbostratus(uint8[1600] memory canvas, uint16 seedNormieId) internal pure {
        for (uint256 j = 0; j < 12;) {
            uint16 pos = uint16(uint256(keccak256(abi.encode(seedNormieId, "nimbostratus-source", j))) % CANVAS_SIZE);
            _paint(canvas, pos, 3);
            unchecked {
                ++j;
            }
        }
    }

    function _paintCascades(
        uint8[1600] memory canvas,
        uint256 abnormieId,
        AbnormieState memory s,
        Cascade[] memory cascades
    ) internal pure returns (uint16 lightningCount, uint16 thunderCount) {
        uint256 n = cascades.length;
        for (uint256 i = 0; i < n;) {
            if (cascades[i].action == 2 && _isEligible(abnormieId, s, cascades[i], i)) {
                uint16 pos = uint16(
                    uint256(
                        keccak256(
                            abi.encode(
                                cascades[i].blockNumber,
                                cascades[i].burnedTokenId,
                                cascades[i].freezeTargetTokenId,
                                "lightning",
                                abnormieId
                            )
                        )
                    ) % CANVAS_SIZE
                );
                _paint(canvas, pos, 3);
                unchecked {
                    ++lightningCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < n;) {
            if (cascades[i].action == 1 && _isEligible(abnormieId, s, cascades[i], i)) {
                _paintThunder(canvas, abnormieId, cascades[i]);
                unchecked {
                    ++thunderCount;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _paintThunder(uint8[1600] memory canvas, uint256 abnormieId, Cascade memory cascade) internal pure {
        bytes32 countSeed = keccak256(
            abi.encode(
                cascade.blockNumber, cascade.burnedTokenId, cascade.freezeTargetTokenId, "thunder-count", abnormieId
            )
        );
        uint256 N = 5 + (uint256(countSeed) % 6);
        for (uint256 j = 0; j < N;) {
            uint16 pos = uint16(
                uint256(
                    keccak256(
                        abi.encode(
                            cascade.blockNumber,
                            cascade.burnedTokenId,
                            cascade.freezeTargetTokenId,
                            "thunder-pos",
                            abnormieId,
                            j
                        )
                    )
                ) % CANVAS_SIZE
            );
            _paint(canvas, pos, 2);
            unchecked {
                ++j;
            }
        }
    }

    function _isEligible(uint256 abnormieId, AbnormieState memory s, Cascade memory cascade, uint256 i)
        internal
        pure
        returns (bool)
    {
        if (uint256(s.pairedAtCascadeIndex) > i) return false;
        if (s.staticAt != 0 && uint256(s.staticAtCascadeIndex) <= i) return false;
        if (uint256(cascade.burnedTokenId) == abnormieId) return false;
        if (uint256(cascade.freezeTargetTokenId) == abnormieId) return false;
        return true;
    }

    function _paint(uint8[1600] memory canvas, uint256 pos, uint8 color) internal pure {
        if (canvas[pos] == 0) {
            canvas[pos] = color;
        } else {
            canvas[pos] = 0;
        }
    }

    function _ownersMatch(uint16 seedNormieId, uint256 abnormieId) internal view returns (bool) {
        address seedOwner;
        try INormies(normiesContract).ownerOf(uint256(seedNormieId)) returns (address o) {
            seedOwner = o;
        } catch {
            return false;
        }
        if (seedOwner == address(0)) return false;

        address abnOwner;
        try IAbnormies(abnormiesContract).ownerOf(abnormieId) returns (address o) {
            abnOwner = o;
        } catch {
            return false;
        }
        return seedOwner == abnOwner;
    }

    function _invertCanvas(uint8[1600] memory canvas) internal pure {
        for (uint256 k = 0; k < CANVAS_SIZE;) {
            uint8 c = canvas[k];
            if (c == 0) canvas[k] = 3;
            else if (c == 3) canvas[k] = 0;
            else if (c == 1) canvas[k] = 2;
            else if (c == 2) canvas[k] = 1;
            unchecked {
                ++k;
            }
        }
    }

    // ---------------------------------------------------------------------
    // SVG with per-row RLE
    // ---------------------------------------------------------------------

    function _renderSvg(uint8[1600] memory canvas)
        internal
        pure
        returns (bytes memory svg, uint16 cirrusVisible, uint16 altocumulusVisible, uint16 nimbostratusVisible)
    {
        DynamicBufferLib.DynamicBuffer memory buf;
        buf.p(
            bytes(
                '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 40 40" shape-rendering="crispEdges">'
            )
        );
        buf.p(bytes('<rect width="40" height="40" fill="#'));
        buf.p(bytes(abi.encodePacked(COLOR_SKY)));
        buf.p(bytes('"/>'));

        for (uint256 y = 0; y < CANVAS_WIDTH;) {
            uint8 runColor = 0;
            uint256 runStart = 0;
            for (uint256 x = 0; x < CANVAS_WIDTH;) {
                uint8 c = canvas[y * CANVAS_WIDTH + x];
                if (c != runColor) {
                    if (runColor != 0) {
                        _emitRect(buf, runStart, y, x - runStart, runColor);
                    }
                    runColor = c;
                    runStart = x;
                }
                if (c == 1) {
                    unchecked {
                        ++cirrusVisible;
                    }
                } else if (c == 2) {
                    unchecked {
                        ++altocumulusVisible;
                    }
                } else if (c == 3) {
                    unchecked {
                        ++nimbostratusVisible;
                    }
                }
                unchecked {
                    ++x;
                }
            }
            if (runColor != 0) {
                _emitRect(buf, runStart, y, CANVAS_WIDTH - runStart, runColor);
            }
            unchecked {
                ++y;
            }
        }

        buf.p(bytes("</svg>"));
        svg = buf.data;
    }

    function _emitRect(DynamicBufferLib.DynamicBuffer memory buf, uint256 x, uint256 y, uint256 w, uint8 color)
        internal
        pure
    {
        buf.p(bytes('<rect x="'));
        buf.p(bytes(LibString.toString(x)));
        buf.p(bytes('" y="'));
        buf.p(bytes(LibString.toString(y)));
        buf.p(bytes('" width="'));
        buf.p(bytes(LibString.toString(w)));
        buf.p(bytes('" height="1" fill="#'));
        buf.p(bytes(abi.encodePacked(_colorFor(color))));
        buf.p(bytes('"/>'));
    }

    function _colorFor(uint8 c) internal pure returns (bytes6) {
        if (c == 0) return COLOR_SKY;
        if (c == 1) return COLOR_CIRRUS;
        if (c == 2) return COLOR_ALTOCUMULUS;
        return COLOR_NIMBOSTRATUS;
    }

    // ---------------------------------------------------------------------
    // JSON construction
    // ---------------------------------------------------------------------

    function _buildJson(UriData memory d) internal view returns (bytes memory) {
        DynamicBufferLib.DynamicBuffer memory buf;
        buf.p(bytes('{"name":"Abnormie #'));
        buf.p(bytes(LibString.toString(d.abnormieId)));
        buf.p(
            bytes('","description":"Abnormies. The weather around your Normies.","image":"data:image/svg+xml;base64,')
        );
        buf.p(bytes(Base64.encode(d.svg)));
        buf.p(bytes('","attributes":['));

        _appendBaseAttrs(buf, d);

        if (d.s.staticAt != 0) {
            _appendStaticAttrs(buf, d);
        }

        bool isFirstStatic = false;
        if (d.s.staticAt != 0) {
            uint16 firstId = IAbnormies(abnormiesContract).firstStaticTokenId();
            bool firstSet = IAbnormies(abnormiesContract).firstStaticSet();
            if (firstSet && uint256(firstId) == d.abnormieId) {
                isFirstStatic = true;
                buf.p(bytes(',{"trait_type":"First Static","value":"Yes"}'));
            }
        }
        // suppress unused-warning
        isFirstStatic;

        if (d.burned) {
            buf.p(bytes(',{"display_type":"number","trait_type":"Dead At","value":'));
            buf.p(bytes(LibString.toString(uint256(d.deadAtBlock))));
            buf.p(bytes("}"));
        }

        buf.p(bytes(',{"trait_type":"Inverted","value":"'));
        buf.p(bytes(d.inverted ? "Yes" : "No"));
        buf.p(bytes('"}'));

        buf.p(bytes("]}"));
        return buf.data;
    }

    function _appendBaseAttrs(DynamicBufferLib.DynamicBuffer memory buf, UriData memory d) internal pure {
        buf.p(bytes('{"trait_type":"Mutability","value":"'));
        buf.p(bytes(d.s.staticAt == 0 ? "Active" : "Static"));
        buf.p(bytes('"},{"trait_type":"Source Life","value":"'));
        buf.p(bytes(d.burned ? "Dead" : "Living"));
        buf.p(bytes('"},{"trait_type":"Source Customized","value":"'));
        buf.p(bytes(d.customized ? "Yes" : "No"));
        buf.p(bytes('"},{"trait_type":"Source Awakened","value":"'));
        buf.p(bytes(d.awakened ? "Yes" : "No"));
        buf.p(bytes('"},{"trait_type":"Seed Normie","value":"'));
        buf.p(bytes(LibString.toString(uint256(d.s.seedNormieId))));
        buf.p(bytes('"},{"display_type":"number","trait_type":"Cirrus Events","value":'));
        buf.p(bytes(LibString.toString(uint256(d.cirrusN))));
        buf.p(bytes('},{"display_type":"number","trait_type":"Lightning Events Received","value":'));
        buf.p(bytes(LibString.toString(uint256(d.lightningCount))));
        buf.p(bytes('},{"display_type":"number","trait_type":"Thunder Events Received","value":'));
        buf.p(bytes(LibString.toString(uint256(d.thunderCount))));
        buf.p(bytes('},{"display_type":"number","trait_type":"Visible Cirrus","value":'));
        buf.p(bytes(LibString.toString(uint256(d.cirrusVisible))));
        buf.p(bytes('},{"display_type":"number","trait_type":"Visible Altocumulus","value":'));
        buf.p(bytes(LibString.toString(uint256(d.altocumulusVisible))));
        buf.p(bytes('},{"display_type":"number","trait_type":"Visible Nimbostratus","value":'));
        buf.p(bytes(LibString.toString(uint256(d.nimbostratusVisible))));
        buf.p(bytes('},{"display_type":"number","trait_type":"Total Coverage","max_value":1600,"value":'));
        buf.p(bytes(LibString.toString(uint256(d.nonSky))));
        buf.p(bytes("}"));
    }

    function _appendStaticAttrs(DynamicBufferLib.DynamicBuffer memory buf, UriData memory d) internal pure {
        buf.p(bytes(',{"display_type":"number","trait_type":"Static At","value":'));
        buf.p(bytes(LibString.toString(uint256(d.s.staticAt))));
        buf.p(bytes('},{"trait_type":"Frozen By","value":"'));
        buf.p(bytes(LibString.toHexString(d.s.frozenBy)));
        buf.p(bytes('"},{"trait_type":"Freeze Action","value":"'));
        buf.p(bytes(d.s.freezeAction == 1 ? "Thunder" : "Lightning"));
        buf.p(bytes('"},{"trait_type":"Frozen After Death","value":"'));
        buf.p(bytes(d.s.seedDeadAtFreeze ? "Yes" : "No"));
        buf.p(bytes('"}'));
    }
}
