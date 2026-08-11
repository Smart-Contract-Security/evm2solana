

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Base64} from "lib/openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

interface IOnChainLMv2 {
    function generateWithCache(
        address cacheAddr,
        uint256 promptLen,
        uint16[] calldata promptTokens,
        uint16 maxNewTokens,
        uint8 temperature,
        uint256 seed
    ) external view returns (uint16[] memory);

    function decode(uint16[] calldata tokens) external view returns (string memory);
}

interface IChainDreamsVisualRenderer {
    function renderSVG(uint256 tokenId, bytes32 genome) external pure returns (string memory);

    function renderLiveSVG(uint256 tokenId, bytes32 genome, address owner)
        external
        pure
        returns (string memory);

    function mood(bytes32 genome) external pure returns (uint256);
    function moodName(uint256 moodId) external pure returns (string memory);

    function blobCount(bytes32 genome) external pure returns (uint256);
    function contourCount(bytes32 genome) external pure returns (uint256);
    function satelliteCount(bytes32 genome) external pure returns (uint256);
    function ditherCount(bytes32 genome) external pure returns (uint256);

    function bgName(bytes32 genome) external pure returns (string memory);
}

/// @title ChainDreamsMetadata
/// @dev Powered by the fully on-chain LLM architecture by @0xdiid.
/// @notice Calls the on-chain LLM in tokenURI(), hashes the generated tokens into a visual genome,
/// and returns fully on-chain JSON metadata with animated SVG image + animation_url.
contract ChainDreamsMetadata {
    using Strings for uint256;

    IOnChainLMv2 public immutable lm;
    IChainDreamsVisualRenderer public immutable renderer;

    bytes32 public immutable SALT;

    address public immutable kvCacheRelic;
    address public immutable kvCacheSignal;
    address public immutable kvCacheVoid;
    address public immutable kvCacheMachine;

    constructor(
        address lmAddress,
        address rendererAddress,
        bytes32 salt,
        address _kvCacheRelic,
        address _kvCacheSignal,
        address _kvCacheVoid,
        address _kvCacheMachine
    ) {
        require(lmAddress != address(0), "BAD_LM");
        require(rendererAddress != address(0), "BAD_RENDERER");

        lm = IOnChainLMv2(lmAddress);
        renderer = IChainDreamsVisualRenderer(rendererAddress);
        SALT = salt;

        kvCacheRelic = _kvCacheRelic;
        kvCacheSignal = _kvCacheSignal;
        kvCacheVoid = _kvCacheVoid;
        kvCacheMachine = _kvCacheMachine;
    }

    function tokenURI(uint256 tokenId, uint8 promptIndex) external view returns (string memory) {
        return _tokenURI(tokenId, promptIndex, address(0), false);
    }

    /// @notice Owner-reactive metadata for websites/agents.
    /// @dev Canonical tokenURI remains stable; this version only changes animation behavior.
    function liveTokenURI(uint256 tokenId, uint8 promptIndex, address owner)
        external
        view
        returns (string memory)
    {
        return _tokenURI(tokenId, promptIndex, owner, true);
    }

    /// @notice Owner-reactive, view-only voice for the artifact.
    /// @dev Uses the current owner, current day, and canonical genome as part of the seed. No storage is changed.
    function speak(uint256 tokenId, uint8 promptIndex, address owner)
        external
        view
        returns (string memory)
    {
        require(promptIndex < 4, "BAD_PROMPT");

        bytes32 genome = canonicalGenome(tokenId, promptIndex);
        uint256 cycle = block.timestamp / 1 days;
        bytes32 seed = dailyDreamSeed(tokenId, promptIndex, owner, cycle, genome);

        return speakFromSeed(promptIndex, seed);
    }

    /// @notice Full daily machine-readable state for agents and live off-chain reconstruction.
    /// @dev Same token + same owner + same day returns the same dream state.
    function dreamState(
    uint256 tokenId,
    uint8 promptIndex,
    address owner
)
    external
    view
    returns (
        uint256 cycle,
        address ownerAddress,
        uint256 orbitSpeed,
        uint256 driftSpeed,
        uint256 ditherTempo,
        bytes32 dreamSeed
    )
{
    require(promptIndex < 4, "BAD_PROMPT");

    cycle = block.timestamp / 1 days;

    dreamSeed = keccak256(
        abi.encodePacked(
            tokenId,
            promptIndex,
            owner,
            cycle,
            SALT,
            "CHAIN_DREAM_DAILY"
        )
    );

    orbitSpeed = 80 + (uint256(dreamSeed) % 120);
    driftSpeed = 48 + ((uint256(dreamSeed) >> 32) % 80);
    ditherTempo = 8 + ((uint256(dreamSeed) >> 64) % 12);

    ownerAddress = owner;
}

    function canonicalGenome(uint256 tokenId, uint8 promptIndex) public view returns (bytes32) {
        require(promptIndex < 4, "BAD_PROMPT");

        uint16[] memory prompt = promptTokens(promptIndex);
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId, promptIndex, SALT)));

        uint16[] memory allTokens = lm.generateWithCache(
            promptCache(promptIndex),
            prompt.length,
            prompt,
            12,
            160,
            seed
        );

        return keccak256(abi.encodePacked(allTokens, tokenId, promptIndex, SALT));
    }

    function dailyDreamSeed(
        uint256 tokenId,
        uint8 promptIndex,
        address owner,
        uint256 cycle,
        bytes32 genome
    ) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                tokenId,
                promptIndex,
                genome,
                owner,
                cycle,
                SALT,
                "CHAIN_DREAM_DAILY"
            )
        );
    }

    function speakFromSeed(uint8 promptIndex, bytes32 dreamSeed)
        internal
        view
        returns (string memory)
    {
        uint16[] memory prompt = promptTokens(promptIndex);

        uint16[] memory allTokens = lm.generateWithCache(
            promptCache(promptIndex),
            prompt.length,
            prompt,
            10,
            150,
            uint256(dreamSeed)
        );

        return cleanGeneratedText(allTokens, prompt.length);
    }

    function _tokenURI(
        uint256 tokenId,
        uint8 promptIndex,
        address owner,
        bool live
    ) internal view returns (string memory) {
        require(promptIndex < 4, "BAD_PROMPT");

        uint16[] memory prompt = promptTokens(promptIndex);
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId, promptIndex, SALT)));

        uint16[] memory allTokens = lm.generateWithCache(
            promptCache(promptIndex),
            prompt.length,
            prompt,
            12,
            160,
            seed
        );

        bytes32 genome = keccak256(abi.encodePacked(allTokens, tokenId, promptIndex, SALT));
        string memory aphorism = cleanGeneratedText(allTokens, prompt.length);
        string memory svg = live
            ? renderer.renderLiveSVG(tokenId, genome, owner)
            : renderer.renderSVG(tokenId, genome);
        string memory svgBase64 = Base64.encode(bytes(svg));

        bytes memory json = abi.encodePacked(
            '{"name":"Chain Dreams C64 #',
            tokenId.toString(),
            '",',
            '"description":"1982 fully on-chain animated C64 memory artifacts generated from an on-chain LLM and rendered fully on-chain as SVG.",',
            '"image":"data:image/svg+xml;base64,',
            svgBase64,
            '",',
            '"animation_url":"data:image/svg+xml;base64,',
            svgBase64,
            '",',
            '"attributes":',
            attributes(tokenId, promptIndex, genome, aphorism),
            "}"
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function cleanGeneratedText(uint16[] memory allTokens, uint256 promptLen) public view returns (string memory) {
        if (allTokens.length <= promptLen) {
            return "A machine dreams in pixels.";
        }

        uint256 genLen = allTokens.length - promptLen;
        uint16[] memory genTokens = new uint16[](genLen);

        for (uint256 i = 0; i < genLen; i++) {
            genTokens[i] = allTokens[promptLen + i];
        }

        string memory raw = lm.decode(genTokens);
        bytes memory textBytes = bytes(raw);

        uint256 start = 0;
        while (
            start < textBytes.length
                && (textBytes[start] == 0x20 || textBytes[start] == 0x0a || textBytes[start] == 0x0d)
        ) {
            start++;
        }

        uint256 end = textBytes.length;
        for (uint256 i = start; i < textBytes.length; i++) {
            bytes1 ch = textBytes[i];

            // Stop before SVG/JSON-dangerous bytes or leaked prefix tags.
            if (
                ch == 0x3C || ch == 0x3E || // < >
                ch == 0x22 || ch == 0x5C || // " \
                ch == 0x26                    // &
            ) {
                end = i;
                break;
            }
        }

        while (
            end > start
                && (textBytes[end - 1] == 0x20 || textBytes[end - 1] == 0x0a || textBytes[end - 1] == 0x0d)
        ) {
            end--;
        }

        uint256 len = end - start;
        if (len == 0) {
            return "A machine dreams in pixels.";
        }

        bool needsPeriod = textBytes[end - 1] != 0x2E;
        bytes memory cleanBytes = new bytes(needsPeriod ? len + 1 : len);

        for (uint256 i = 0; i < len; i++) {
            cleanBytes[i] = textBytes[start + i];
        }

        if (needsPeriod) {
            cleanBytes[len] = 0x2E;
        }

        return string(cleanBytes);
    }

    function attributes(
        uint256,
        uint8 promptIndex,
        bytes32 genome,
        string memory aphorism
    ) public view returns (string memory) {
        uint256 m = renderer.mood(genome);

        return string(
            abi.encodePacked(
                "[",
                '{"trait_type":"Prompt","value":"',
                promptName(promptIndex),
                '"},',
                '{"trait_type":"Aphorism","value":"',
                aphorism,
                '"},',
                '{"trait_type":"Mood","value":"',
                renderer.moodName(m),
                '"},',
                '{"trait_type":"Blob Count","value":',
                renderer.blobCount(genome).toString(),
                "},",
                '{"trait_type":"Contour Count","value":',
                renderer.contourCount(genome).toString(),
                "},",
                '{"trait_type":"Satellite Count","value":',
                renderer.satelliteCount(genome).toString(),
                "},",
                '{"trait_type":"Background","value":"',
                renderer.bgName(genome),
                '"},',
                '{"trait_type":"Dither","value":"',
                ditherName(renderer.ditherCount(genome)),
                '"}',
                "]"
            )
        );
    }

    function promptCache(uint8 p) public view returns (address) {
        if (p == 0) return kvCacheRelic;
        if (p == 1) return kvCacheSignal;
        if (p == 2) return kvCacheVoid;
        return kvCacheMachine;
    }

    function promptName(uint8 p) public pure returns (string memory) {
        if (p == 0) return "Relic";
        if (p == 1) return "Signal";
        if (p == 2) return "Void";
        return "Machine";
    }

    function ditherName(uint256 count) public pure returns (string memory) {
        if (count == 0) return "None";
        if (count == 1) return "Single Band";
        if (count == 2) return "Double Band";
        return "Triple Band";
    }

    function promptTokens(uint8 p) public pure returns (uint16[] memory t) {
        if (p == 0) {
            // Relic / scarce
            t = new uint16[](8);
            t[0] = 1;
            t[1] = 1946;
            t[2] = 2040;
            t[3] = 1955;
            t[4] = 1965;
            t[5] = 295;
            t[6] = 331;
            t[7] = 2041;
        } else if (p == 1) {
            // Signal / rising
            t = new uint16[](7);
            t[0] = 1;
            t[1] = 1946;
            t[2] = 2040;
            t[3] = 1956;
            t[4] = 293;
            t[5] = 299;
            t[6] = 2041;
        } else if (p == 2) {
            // Void / falling
            t = new uint16[](7);
            t[0] = 1;
            t[1] = 1946;
            t[2] = 2040;
            t[3] = 1967;
            t[4] = 388;
            t[5] = 299;
            t[6] = 2041;
        } else {
            // Machine / crowded
            t = new uint16[](8);
            t[0] = 1;
            t[1] = 1946;
            t[2] = 2040;
            t[3] = 1965;
            t[4] = 1453;
            t[5] = 1954;
            t[6] = 266;
            t[7] = 2041;
        }
    }
}
