// SPDX-License-Identifier: MIT

import {ERC721} from "../ERC721.sol";

/**
 * @dev ERC-721 token with storage based token URI management.
 */
abstract contract ERC721URIStorage is ERC721 {
    bytes4 private constant ERC4906_INTERFACE_ID = bytes4(0x49064906);

    mapping(uint64 tokenId => string) private _tokenURIs;

    event MetadataUpdate(uint64 tokenId);

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || ERC721.supportsInterface(interfaceId);
    }

    function tokenURI(uint64 tokenId) public view virtual returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721: invalid token ID");

        string memory base = _baseURI();
        string memory suffix = _suffixURI(tokenId);

        if (bytes(base).length == 0) {
            return suffix;
        }
        if (bytes(suffix).length > 0) {
            return string.concat(base, suffix);
        }

        return ERC721.tokenURI(tokenId);
    }

    function _setTokenURI(uint64 tokenId, string memory _tokenURI) internal virtual {
        _tokenURIs[tokenId] = _tokenURI;
        emit MetadataUpdate(tokenId);
    }

    function _suffixURI(uint64 tokenId) internal view virtual returns (string memory) {
        return _tokenURIs[tokenId];
    }
}