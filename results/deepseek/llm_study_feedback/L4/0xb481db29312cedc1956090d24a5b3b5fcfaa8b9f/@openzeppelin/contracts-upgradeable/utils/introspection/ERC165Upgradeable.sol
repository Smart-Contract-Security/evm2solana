// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    modifier initializer() {
        require(!_initialized, "Initializable: contract is already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }
}

abstract contract ERC165Upgradeable is Initializable, IERC165 {
    function __ERC165_init() internal onlyInitializing {
    }

    function __ERC165_init_unchained() internal onlyInitializing {
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == bytes4(bytes8(type(IERC165).interfaceId));
    }
}