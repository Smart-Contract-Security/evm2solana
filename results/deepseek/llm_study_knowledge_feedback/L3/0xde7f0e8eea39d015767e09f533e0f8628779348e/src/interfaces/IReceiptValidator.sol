// SPDX-License-Identifier: MIT
import {Receipt, DiscountParams} from "../common/ZuCityTypes.sol";

@program_id("11111111111111111111111111111111")
interface IReceiptValidator {
    @account(validatorAccount)
    function validateBuyer(address buyer) external view returns (bool);

    @account(validatorAccount)
    function validateReceipt(Receipt memory b) external view returns (bool);

    @account(validatorAccount)
    function discount(DiscountParams memory discountData) external view returns (uint64);

    @account(validatorAccount)
    function getDiscountsAvailable(DiscountParams memory discountData) external view returns (uint64[] memory);
}