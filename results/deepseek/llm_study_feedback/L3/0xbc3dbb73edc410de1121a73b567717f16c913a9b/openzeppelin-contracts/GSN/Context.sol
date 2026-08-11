// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.tx_authority.key;
    }

    function _msgData() internal view returns (bytes memory) {
        return abi.encode(tx.accounts);
    }
}