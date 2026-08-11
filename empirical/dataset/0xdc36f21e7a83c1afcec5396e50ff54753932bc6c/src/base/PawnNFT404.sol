// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PawnERC20} from "./PawnERC20.sol";
import {TierMath} from "../lib/TierMath.sol";
import {IPawnTreasury} from "../interfaces/IPawnTreasury.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract PawnNFT404 is PawnERC20 {
    address public immutable TREASURY;

    mapping(address => bool) internal _isExcludedFromFee;
    mapping(address => bool) public nftExempt;

    mapping(uint256 => address) private _nftOwner;
    mapping(uint256 => uint8) private _nftTier;
    mapping(address => uint256) internal _nftCount;
    mapping(address => mapping(uint8 => uint256)) internal _holderTierCount;

    uint256 internal _nextTokenId = 1;

    string internal _customT1;
    string internal _customT2;
    string internal _customT3;
    string internal _customT4;

    event NFTMinted(address indexed owner, uint256 indexed tokenId, uint8 tier);
    event NFTBurned(address indexed owner, uint256 indexed tokenId, uint8 tier, uint8 burnReason);
    event PawnArtSet(uint8 indexed tier, string uri);

    string private constant _SVG_T1 =
        '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350"><rect width="350" height="350" fill="#000"/><circle cx="175" cy="175" r="110" fill="none" stroke="#22c55e" stroke-width="8"/><circle cx="175" cy="175" r="100" fill="#fff"/><text x="175" y="195" text-anchor="middle" font-family="serif" font-size="72" fill="#000">I</text></svg>';

    string private constant _SVG_T2 =
        '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350"><rect width="350" height="350" fill="#000"/><circle cx="175" cy="175" r="110" fill="none" stroke="#3b82f6" stroke-width="8"/><rect x="105" y="105" width="140" height="140" fill="#fff" transform="rotate(45 175 175)"/><text x="175" y="195" text-anchor="middle" font-family="serif" font-size="64" fill="#000">II</text></svg>';

    string private constant _SVG_T3 =
        '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350"><rect width="350" height="350" fill="#000"/><circle cx="175" cy="175" r="110" fill="none" stroke="#f59e0b" stroke-width="8"/><polygon points="175,75 255,230 95,230" fill="#fff"/><text x="175" y="235" text-anchor="middle" font-family="serif" font-size="52" fill="#000">III</text></svg>';

    string private constant _SVG_T4 =
        '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350"><rect width="350" height="350" fill="#000"/><circle cx="175" cy="175" r="110" fill="none" stroke="#ef4444" stroke-width="8"/><polygon points="175,85 245,175 175,265 105,175" fill="#fff"/><text x="175" y="195" text-anchor="middle" font-family="serif" font-size="56" fill="#000">IV</text></svg>';

    constructor(address treasury_) {
        TREASURY = treasury_;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _nftOwner[tokenId];
        require(o != address(0), "nonexistent token");
        return o;
    }

    function tokenTier(uint256 tokenId) external view returns (uint8) {
        require(_nftOwner[tokenId] != address(0), "nonexistent token");
        return _nftTier[tokenId];
    }

    function nftBalanceOf(address owner_) external view returns (uint256) {
        return _nftCount[owner_];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_nftOwner[tokenId] != address(0), "nonexistent token");
        uint8 tier = _nftTier[tokenId];

        string memory tierLabel;
        string memory svgRaw;

        if (tier == 1) {
            tierLabel = "I";
            svgRaw = _SVG_T1;
        } else if (tier == 2) {
            tierLabel = "II";
            svgRaw = _SVG_T2;
        } else if (tier == 3) {
            tierLabel = "III";
            svgRaw = _SVG_T3;
        } else {
            tierLabel = "IV";
            svgRaw = _SVG_T4;
        }

        string memory customUri = (tier == 1) ? _customT1 : (tier == 2) ? _customT2 : (tier == 3) ? _customT3 : _customT4;

        string memory imageUri;
        if (bytes(customUri).length > 0) {
            imageUri = customUri;
        } else {
            imageUri = string(
                abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svgRaw)))
            );
        }

        string memory json = string(
            abi.encodePacked(
                '{"name":"PAWN Type ',
                tierLabel,
                " #",
                Strings.toString(tokenId),
                '","description":"PAWN ERC-5D - Type ',
                tierLabel,
                '","image":"',
                imageUri,
                '"}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _reconcileNFTs(address holder, bool isSell) internal {
        uint256 expected = _balances[holder] / 1e18;
        uint256 actual = _nftCount[holder];
        if (expected > actual) {
            uint256 toMint = expected - actual;
            for (uint256 i; i < toMint; i++) _mintNFT(holder);
        } else if (expected < actual) {
            uint256 toBurn = actual - expected;
            for (uint256 i; i < toBurn; i++) _burnLastNFT(holder, isSell);
        }
    }

    function _mintNFT(address holder) internal {
        uint256 tokenId = _nextTokenId++;
        uint8 tier = TierMath.tierFromTokenId(tokenId);
        _nftOwner[tokenId] = holder;
        _nftTier[tokenId] = tier;
        _nftCount[holder]++;
        _holderTierCount[holder][tier]++;

        if (TREASURY != address(0)) {
            try IPawnTreasury(TREASURY).onNFTMint(holder, tier) {} catch {}
        }
        emit NFTMinted(holder, tokenId, tier);
        _emitERC721Transfer(address(0), holder, tokenId);
    }

    function _burnLastNFT(address holder, bool isSell) internal {
        uint256 tokenId = _findLastTokenId(holder);
        require(tokenId != 0, "no NFT to burn");

        uint8 tier = _nftTier[tokenId];
        uint8 burnReason = isSell ? 0 : 1;

        if (TREASURY != address(0)) {
            try IPawnTreasury(TREASURY).onNFTBurn(holder, tier, isSell) {} catch {}
        }

        delete _nftOwner[tokenId];
        delete _nftTier[tokenId];
        _nftCount[holder]--;
        if (_holderTierCount[holder][tier] > 0) _holderTierCount[holder][tier]--;

        emit NFTBurned(holder, tokenId, tier, burnReason);
        _emitERC721Transfer(holder, address(0), tokenId);
    }

    function _emitERC721Transfer(address from, address to, uint256 tokenId) private {
        assembly {
            let sig := 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
            log4(0, 0, sig, and(from, 0xffffffffffffffffffffffffffffffffffffffff), and(to, 0xffffffffffffffffffffffffffffffffffffffff), tokenId)
        }
    }

    function _findLastTokenId(address holder) internal view returns (uint256) {
        uint256 total = _nextTokenId - 1;
        for (uint256 id = total; id >= 1; id--) {
            if (_nftOwner[id] == holder) return id;
        }
        return 0;
    }
}
