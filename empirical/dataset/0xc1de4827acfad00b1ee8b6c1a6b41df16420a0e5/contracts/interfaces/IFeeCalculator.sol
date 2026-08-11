// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IFeeCalculator {
    struct FeeBreakdown {
        uint256 totalFeeBps;     // scaled by 1e4 (bps * 1e4 == one bp)... actually FP scale below
        uint256 inventoryFeeBps;
        uint256 depegFeeBps;
        uint256 feeAmount;       // in input-token native decimals
        uint256 netIn;
        uint256 amountOut;       // in output-token native decimals
        bool routeDisabled;
    }

    /// @notice Quote a swap. All fee bps are scaled by FEE_BPS_SCALE (1e4) so 1 bp == 1e4.
    function quote(address assetIn, address assetOut, uint256 amountIn)
        external
        view
        returns (FeeBreakdown memory);

    function FEE_BPS_SCALE() external view returns (uint256);
}
