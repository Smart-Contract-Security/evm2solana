// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILSDAdapter {
    /// @notice LSD 汇率信息结构体
    struct ExchangeRateInfo {
        // LSD 相关信息
        address lsdToken; // LSD 代币地址
        string lsdSymbol; // LSD 代币符号（如 "stETH", "rETH"）
        uint8 lsdDecimals; // LSD 代币精度
        // 底层资产相关信息
        address underlyingAsset; // 底层资产地址
        string underlyingSymbol; // 底层资产符号（如 "ETH", "BNB"）
        uint8 underlyingDecimals; // 底层资产精度
        bool isNative; // 底层是否为原生代币（如 ETH/BNB）
        // 汇率信息
        uint256 rate; // 汇率：1 单位 LSD 对应的底层资产数量（已按底层资产decimals缩放）
        uint256 timestamp; // 查询时的区块时间戳
    }

    /// @notice 获取 LSD 代币与底层资产的汇率
    /// @dev 返回的汇率应以底层资产的最小单位（根据其decimals）表示，
    ///      即 1 单位 LSD 代币（根据其decimals）可兑换多少底层资产
    /// @param lsdTokenAddress LSD 代币的地址
    /// @return info 汇率信息结构体
    function getExchangeRate(address lsdTokenAddress) external view returns (ExchangeRateInfo memory info);

    /// @notice LSD 数量换算到底层资产数量
    /// @dev 返回换算后的底层资产数量及完整的汇率信息
    /// @param lsdTokenAddress LSD 代币的地址
    /// @param lsdAmount LSD 代币数量
    /// @return underlyingAmount 换算后的底层资产数量
    /// @return info 汇率信息结构体
    function convertToUnderlying(address lsdTokenAddress, uint256 lsdAmount)
        external
        view
        returns (uint256 underlyingAmount, ExchangeRateInfo memory info);
}

