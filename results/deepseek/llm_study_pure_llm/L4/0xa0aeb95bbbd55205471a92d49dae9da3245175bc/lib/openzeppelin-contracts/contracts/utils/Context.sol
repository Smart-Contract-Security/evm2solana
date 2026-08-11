// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view returns (uint256) {
        return 0;
    }
}