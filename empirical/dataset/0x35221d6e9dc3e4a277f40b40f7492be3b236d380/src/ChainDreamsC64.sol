
//  ██████╗██╗  ██╗ █████╗ ██╗███╗   ██╗    ██████╗ ██████╗ ███████╗ █████╗ ███╗   ███╗███████╗
// ██╔════╝██║  ██║██╔══██╗██║████╗  ██║    ██╔══██╗██╔══██╗██╔════╝██╔══██╗████╗ ████║██╔════╝
// ██║     ███████║███████║██║██╔██╗ ██║    ██║  ██║██████╔╝█████╗  ███████║██╔████╔██║███████╗
// ██║     ██╔══██║██╔══██║██║██║╚██╗██║    ██║  ██║██╔══██╗██╔══╝  ██╔══██║██║╚██╔╝██║╚════██║
// ╚██████╗██║  ██║██║  ██║██║██║ ╚████║    ██████╔╝██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████║
//  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721SeaDrop} from "./ERC721SeaDrop.sol";

interface IChainDreamsMetadata {
    function tokenURI(uint256 tokenId, uint8 promptIndex) external view returns (string memory);

    function liveTokenURI(uint256 tokenId, uint8 promptIndex, address owner)
        external
        view
        returns (string memory);

    function speak(uint256 tokenId, uint8 promptIndex, address owner)
        external
        view
        returns (string memory);

    function dreamState(uint256 tokenId, uint8 promptIndex, address owner)
        external
        view
        returns (
            uint256 cycle,
            address ownerAddress,
            uint256 orbitSpeed,
            uint256 driftSpeed,
            uint256 ditherTempo,
            bytes32 dreamSeed
        );
}

contract ChainDreamsC64 is ERC721SeaDrop {
    uint256 public constant MAX_SUPPLY = 1982;

    IChainDreamsMetadata public immutable metadataRenderer;

    constructor(address[] memory allowedSeaDrop, address metadataRendererAddress)
        ERC721SeaDrop("Chain Dreams C64", "DREAM", allowedSeaDrop)
    {
        require(metadataRendererAddress != address(0), "BAD_METADATA");
        metadataRenderer = IChainDreamsMetadata(metadataRendererAddress);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "NOT_MINTED");
        return metadataRenderer.tokenURI(tokenId, promptOf(tokenId));
    }

    function liveTokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "NOT_MINTED");
        return metadataRenderer.liveTokenURI(tokenId, promptOf(tokenId), ownerOf(tokenId));
    }

    function speak(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "NOT_MINTED");
        return metadataRenderer.speak(tokenId, promptOf(tokenId), ownerOf(tokenId));
    }

    function dreamState(uint256 tokenId)
        external
        view
        returns (
            uint256 cycle,
            address owner,
            uint256 orbitSpeed,
            uint256 driftSpeed,
            uint256 ditherTempo,
            bytes32 dreamSeed
        )
    {
        require(_exists(tokenId), "NOT_MINTED");

        return metadataRenderer.dreamState(
            tokenId,
            promptOf(tokenId),
            ownerOf(tokenId)
        );
    }

    function promptOf(uint256 tokenId) public view returns (uint8) {
        return uint8(
            uint256(
                keccak256(
                    abi.encodePacked(address(this), tokenId, "CHAIN_DREAMS_PROMPT")
                )
            ) % 4
        );
    }

    function promptName(uint8 p) public pure returns (string memory) {
        if (p == 0) return "Relic";
        if (p == 1) return "Signal";
        if (p == 2) return "Void";
        return "Machine";
    }
}