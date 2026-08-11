// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IJudgmentOracleAdapter {
    function getRoundStartPrices(bytes[] calldata priceUpdateData)
        external
        payable
        returns (uint256 marketPriceWad, uint256 ethUsdPriceWad);

    function getRoundSettlementPrice(bytes[] calldata priceUpdateData)
        external
        payable
        returns (uint256 marketPriceWad);

    function getUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256);
}
