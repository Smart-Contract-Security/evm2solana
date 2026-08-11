// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721AC} from "@limitbreak/creator-token-standards/src/erc721c/ERC721AC.sol";
import {OwnableBasic} from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import {BasicRoyalties} from "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {PrismaRenderer} from "./PrismaRenderer.sol";

/// @notice Minimal ERC721C collection scaffold for a fully on-chain NFT drop.
/// @dev Limit Break import paths may need adjustment depending on the exact package version.
contract PrismaGenesis is ERC721AC, OwnableBasic, BasicRoyalties {
    uint256 public constant MINT_PRICE = 0.0002 ether;
    uint256 public immutable maxSupply;
    string public baseDescription;
    uint256 private _nextTokenIdValue;
    string public collectionName;
    string public collectionSymbol;
    mapping(address => bool) public hasClaimedFreeMint;

    mapping(uint256 => PrismaRenderer.TokenTraits) private _traitsByToken;

    constructor(
        address royaltyReceiver_,
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory description_,
        address owner_
    ) ERC721AC(name_, symbol_) BasicRoyalties(royaltyReceiver_, 250) {
        maxSupply = maxSupply_;
        baseDescription = description_;
        collectionName = name_;
        collectionSymbol = symbol_;
        transferOwnership(owner_);
    }

    function mint(address to, uint256 quantity) external payable {
        require(quantity > 0, "Invalid quantity");
        require(_nextTokenIdValue + quantity <= maxSupply, "Max supply exceeded");

        uint256 cost = 0;
        if (!hasClaimedFreeMint[msg.sender]) {
            hasClaimedFreeMint[msg.sender] = true;
            if (quantity > 1) {
                cost = MINT_PRICE * (quantity - 1);
            }
        } else {
            cost = MINT_PRICE * quantity;
        }

        require(msg.value >= cost, "Insufficient payment");

        for (uint256 i = 0; i < quantity; ++i) {
            _safeMint(to, 1);
            _setTokenTraits(_nextTokenIdValue);
            unchecked {
                ++_nextTokenIdValue;
            }
        }

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    function withdraw(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        recipient.transfer(address(this).balance);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        return PrismaRenderer.render(_traitsByToken[tokenId], tokenId, collectionName);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721AC, ERC2981)
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f || // ERC721Metadata
            interfaceId == 0x2a55205a || // ERC2981
            ERC721AC.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function _setTokenTraits(uint256 tokenId) internal {
        _traitsByToken[tokenId] = _generateTraits(tokenId);
    }

    function _generateTraits(uint256 tokenId) internal view returns (PrismaRenderer.TokenTraits memory traits) {
        uint256 seed = uint256(keccak256(abi.encodePacked(address(this), tokenId, collectionName)));
        uint256 bgRoll = seed % 100;
        uint256 coreRoll = uint256(keccak256(abi.encodePacked(seed, "core"))) % 100;

        if (bgRoll < 40) {
            traits.backgroundName = "Cosmic Nebula";
        } else if (bgRoll < 70) {
            traits.backgroundName = "Deep Space";
        } else if (bgRoll < 90) {
            traits.backgroundName = "Cyberpunk Purple";
        } else {
            traits.backgroundName = "Legendary Gold";
        }

        if (coreRoll < 20) {
            traits.coreName = "Classic Ethereum";
        } else if (coreRoll < 40) {
            traits.coreName = "Fire Ruby";
        } else if (coreRoll < 60) {
            traits.coreName = "Emerald Green";
        } else if (coreRoll < 80) {
            traits.coreName = "Cosmic Void";
        } else {
            traits.coreName = "Pure Sapphire";
        }

        traits.rings = seed % 7;
        traits.shards = uint256(keccak256(abi.encodePacked(seed, "shards"))) % 31;
        traits.seed = seed;
        traits.rarityScore = 30 + (traits.rings * 4) + (traits.shards * 3) / 2;
        if (keccak256(bytes(traits.backgroundName)) == keccak256(bytes("Deep Space"))) traits.rarityScore += 15;
        if (keccak256(bytes(traits.backgroundName)) == keccak256(bytes("Cyberpunk Purple"))) traits.rarityScore += 25;
        if (keccak256(bytes(traits.backgroundName)) == keccak256(bytes("Legendary Gold"))) traits.rarityScore += 55;

        if (keccak256(bytes(traits.coreName)) == keccak256(bytes("Fire Ruby"))
            || keccak256(bytes(traits.coreName)) == keccak256(bytes("Emerald Green"))) traits.rarityScore += 10;
        if (keccak256(bytes(traits.coreName)) == keccak256(bytes("Cosmic Void"))) traits.rarityScore += 20;
        if (keccak256(bytes(traits.coreName)) == keccak256(bytes("Pure Sapphire"))) traits.rarityScore += 15;

        traits.rarityClass = traits.rarityScore < 50
            ? "Common"
            : traits.rarityScore < 80
                ? "Rare"
                : traits.rarityScore < 110 ? "Epic" : "Legendary";
    }
}
