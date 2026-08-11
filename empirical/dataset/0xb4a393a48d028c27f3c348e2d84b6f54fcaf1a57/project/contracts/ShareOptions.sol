// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

contract ShareOptions {
    struct Options {
        string name;
        string symbol;
        uint8 decimals;
        address owner;
        uint64 annualDiscountRateSlope;
        uint64 annualDiscountRateBase;
        uint64 minIdleFactor;
        uint64 maxIdleFactor;
    }
}
