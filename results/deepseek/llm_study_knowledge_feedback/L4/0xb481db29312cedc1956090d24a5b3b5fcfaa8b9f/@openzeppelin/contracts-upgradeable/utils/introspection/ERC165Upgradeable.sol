// SPDX-License-Identifier: MIT

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract ERC165Upgradeable is IERC165 {
    bool private _initialized;
    bool private _initializing;

    modifier onlyInitializing() {
        require(_initializing, "Not initializing");
        _;
    }

    function __ERC165_init() internal onlyInitializing {
    }

    function __ERC165_init_unchained() internal onlyInitializing {
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == bytes4(type(IERC165).interfaceId);
    }
}