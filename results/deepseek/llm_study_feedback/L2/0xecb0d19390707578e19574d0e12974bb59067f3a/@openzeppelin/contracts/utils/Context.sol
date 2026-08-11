// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.origin;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal pure returns (uint256) {
        return 0;
    }
}