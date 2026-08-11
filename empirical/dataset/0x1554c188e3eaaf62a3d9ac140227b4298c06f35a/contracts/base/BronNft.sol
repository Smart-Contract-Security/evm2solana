// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IBronNft.sol";

abstract contract BronNft is IBronNft, ERC721Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using Strings for uint256;

    /// @custom:storage-location erc7201:bron.storage.BronNft
    struct BronNftStorage {
        string baseTokenURI;
        string contractMetadataURI;
    }

    // keccak256(abi.encode(uint256(keccak256("BronNft")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BronNftLocation = 0xb20677f6042114bc53b333a6c867cea5f517ce90abf86b5fb9920316eeaba200;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function getBronNftStorage() private pure returns (BronNftStorage storage $) {
        assembly {
            $.slot := BronNftLocation
        }
    }

    function __BronNft_init(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        string memory _contractURI,
        address _owner
    ) internal onlyInitializing {
        __ERC721_init(_name, _symbol);
        __Ownable_init(_owner);
        __Pausable_init();

        BronNftStorage storage $ = getBronNftStorage();
        $.baseTokenURI = _baseURI;
        $.contractMetadataURI = _contractURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);
        BronNftStorage storage $ = getBronNftStorage();
        return string(abi.encodePacked($.baseTokenURI, tokenId.toString()));
    }

    function contractURI() public view virtual returns (string memory) {
        BronNftStorage storage $ = getBronNftStorage();
        return $.contractMetadataURI;
    }

    function mint(address to, uint256 tokenId) external virtual onlyOwner {
        _safeMint(to, tokenId);
    }

    function mintBatch(address to, uint256[] calldata tokenIds) external virtual onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _safeMint(to, tokenIds[i]);
        }
    }

    function burn(uint256 tokenId) external virtual onlyOwner {
        _update(address(0), tokenId, _msgSender());
    }

    function setBaseURI(string memory _baseURI) external virtual onlyOwner {
        BronNftStorage storage $ = getBronNftStorage();
        $.baseTokenURI = _baseURI;
        emit BaseURIUpdated(_baseURI);
    }

    function setContractURI(string memory _uri) external virtual onlyOwner {
        BronNftStorage storage $ = getBronNftStorage();
        $.contractMetadataURI = _uri;
        emit ContractURIUpdated(_uri);
    }

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override whenNotPaused() returns (address)  {
        return super._update(to, tokenId, auth);
    }
}
