// SPDX-License-Identifier: MIT

import {IERC721Enumerable} from "./IERC721Enumerable.sol";

abstract contract ERC721Enumerable is IERC721Enumerable {
    mapping(address owner => mapping(uint64 index => uint64)) private _ownedTokens;
    mapping(uint64 tokenId => uint64) private _ownedTokensIndex;

    uint64[] private _allTokens;
    mapping(uint64 tokenId => uint64) private _allTokensIndex;

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == bytes4(type(IERC721Enumerable).interfaceId);
    }

    function tokenOfOwnerByIndex(address owner, uint64 index) public view virtual returns (uint64) {
        if (index >= balanceOf(owner)) {
            revert();
        }
        return _ownedTokens[owner][index];
    }

    function totalSupply() public view virtual returns (uint64) {
        return uint64(_allTokens.length);
    }

    function tokenByIndex(uint64 index) public view virtual returns (uint64) {
        if (index >= totalSupply()) {
            revert();
        }
        return _allTokens[index];
    }

    function balanceOf(address owner) public view virtual returns (uint64);

    function _update(address to, uint64 tokenId, address auth) internal virtual returns (address) {
        address previousOwner = address(0);

        if (previousOwner == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (previousOwner != to) {
            _removeTokenFromOwnerEnumeration(previousOwner, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (previousOwner != to) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }

        return previousOwner;
    }

    function _addTokenToOwnerEnumeration(address to, uint64 tokenId) private {
        uint64 length = balanceOf(to) - 1;
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _addTokenToAllTokensEnumeration(uint64 tokenId) private {
        _allTokensIndex[tokenId] = uint64(_allTokens.length);
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint64 tokenId) private {
        uint64 lastTokenIndex = balanceOf(from);
        uint64 tokenIndex = _ownedTokensIndex[tokenId];

        mapping(uint64 index => uint64) storage _ownedTokensByOwner = _ownedTokens[from];

        if (tokenIndex != lastTokenIndex) {
            uint64 lastTokenId = _ownedTokensByOwner[lastTokenIndex];

            _ownedTokensByOwner[tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _ownedTokensIndex[tokenId];
        delete _ownedTokensByOwner[lastTokenIndex];
    }

    function _removeTokenFromAllTokensEnumeration(uint64 tokenId) private {
        uint64 lastTokenIndex = uint64(_allTokens.length - 1);
        uint64 tokenIndex = _allTokensIndex[tokenId];

        uint64 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId;
        _allTokensIndex[lastTokenId] = tokenIndex;

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }

    function _increaseBalance(address account, uint128 amount) internal virtual {
        if (amount > 0) {
            revert();
        }
    }
}