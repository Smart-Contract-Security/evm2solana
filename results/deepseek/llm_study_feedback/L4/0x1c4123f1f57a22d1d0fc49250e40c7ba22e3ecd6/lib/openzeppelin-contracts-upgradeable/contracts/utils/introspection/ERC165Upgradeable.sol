// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

abstract contract ERC165Upgradeable is IERC165 {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initializing = true;
        _;
        _initializing = false;
        _initialized = true;
    }

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