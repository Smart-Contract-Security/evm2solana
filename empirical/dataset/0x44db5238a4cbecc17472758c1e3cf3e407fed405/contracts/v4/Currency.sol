// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

type Currency is address;

library CurrencyLibrary {
    function isAddressZero(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == address(0);
    }
}
