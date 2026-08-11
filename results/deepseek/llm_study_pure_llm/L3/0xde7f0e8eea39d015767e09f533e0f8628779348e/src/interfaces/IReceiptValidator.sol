// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Receipt, DiscountParams} from "../common/ZuCityTypes.sol";

interface IReceiptValidator {
    function validateBuyer(address buyer) external view returns (bool);
    function validateReceipt(Receipt memory b) external view returns (bool);
    function discount(DiscountParams memory discountData) external view returns (uint256);
    function getDiscountsAvailable(DiscountParams memory discountData) external view returns (uint256[] memory);
}