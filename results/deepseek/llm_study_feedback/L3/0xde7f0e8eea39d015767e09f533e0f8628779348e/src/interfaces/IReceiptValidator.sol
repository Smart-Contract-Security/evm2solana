// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

struct Receipt {
    uint256 id;
    address buyer;
    uint256 amount;
    bytes data;
}

struct DiscountParams {
    uint256 base;
    uint256 rate;
    bytes extra;
}

interface IReceiptValidator {
    function validateBuyer(address buyer) external view returns (bool);
    function validateReceipt(Receipt memory b) external view returns (bool);
    function discount(DiscountParams memory discountData) external view returns (uint256);
    function getDiscountsAvailable(DiscountParams memory discountData) external view returns (uint256[] memory);
}