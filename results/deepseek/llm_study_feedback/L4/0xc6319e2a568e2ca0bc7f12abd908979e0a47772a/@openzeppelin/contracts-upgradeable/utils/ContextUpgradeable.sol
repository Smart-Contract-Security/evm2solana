// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract ContextUpgradeable {
    function __Context_init() internal {
    }

    function __Context_init_unchained() internal {
    }

    function _msgSender() internal view returns (address) {
        return tx.accounts[0];
    }

    function _msgData() internal view returns (bytes memory) {
        return tx.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }

    uint256[50] private __gap;
}