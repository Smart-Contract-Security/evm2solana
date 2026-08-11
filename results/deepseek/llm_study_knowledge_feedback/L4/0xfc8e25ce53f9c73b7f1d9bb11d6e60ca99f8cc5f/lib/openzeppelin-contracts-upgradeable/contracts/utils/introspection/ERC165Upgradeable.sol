// SPDX-License-Identifier: MIT

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract ERC165Upgradeable {
    function __ERC165_init() internal {
    }

    function __ERC165_init_unchained() internal {
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == bytes4(type(IERC165).interfaceId);
    }
}