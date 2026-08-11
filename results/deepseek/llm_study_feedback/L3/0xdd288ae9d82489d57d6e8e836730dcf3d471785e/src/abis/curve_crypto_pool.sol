// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import 'solana';

interface CurveCryptoPool {
    // 基本池子信息
    function token() external view returns (address);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    
    // 不变量参数
    function A() external view returns (uint256);
    function gamma() external view returns (uint256);
    function D() external view returns (uint256);
    
    // A和gamma参数调整相关
    function initial_A_gamma() external view returns (uint256);
    function future_A_gamma() external view returns (uint256);
    function initial_A_gamma_time() external view returns (uint256);
    function future_A_gamma_time() external view returns (uint256);
    
    // 价格相关
    function price_scale() external view returns (uint256);  // 2币种池版本
    function price_scale(uint256 k) external view returns (uint256);  // 3币种池版本
    function price_oracle(uint256 k) external view returns (uint256);
    function virtual_price() external view returns (uint256);
    
    // 手续费相关
    function fee() external view returns (uint256);
    function mid_fee() external view returns (uint256);
    function out_fee() external view returns (uint256);
    function admin_fee() external view returns (uint256);
    function fee_gamma() external view returns (uint256);
    function future_fee_gamma() external view returns (uint256);

    // 其他参数
    function allowed_extra_profit() external view returns (uint256);
    function adjustment_step() external view returns (uint256);
    function ma_half_time() external view returns (uint256);
    function is_killed() external view returns (bool);

    // 交易函数
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);

    // Math 合约地址（仅 CurveCryptoNG 2币/3币池支持）
    function MATH() external view returns (address);
}

interface CurveCryptoMath {
    // newton_y 仅存在于 CryptoMath（v2.x.x），StableMath（v0.x.x）没有此方法
    function newton_y(uint256 ANN, uint256 gamma, uint256[2] calldata x, uint256 D, uint256 i) external view returns (uint256);
}