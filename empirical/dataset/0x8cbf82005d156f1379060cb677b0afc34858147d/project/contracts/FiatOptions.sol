// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

contract FiatOptions {
    struct Options {
        string name;
        string symbol;
        uint8 decimals;
        address owner;
    }
}
