// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import 'solana';

interface CurveCryptoPool {
    // Basic pool info
    function token() external view returns (address);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);

    // Invariant parameters
    function A() external view returns (uint256);
    function gamma() external view returns (uint256);
    function D() external view returns (uint256);

    // A and gamma parameter adjustment
    function initial_A_gamma() external view returns (uint256);
    function future_A_gamma() external view returns (uint256);
    function initial_A_gamma_time() external view returns (uint256);
    function future_A_gamma_time() external view returns (uint256);

    // Price related
    function price_scale() external view returns (uint256); // 2-coin pool version
    function price_scale(uint256 k) external view returns (uint256); // 3-coin pool version
    function price_oracle(uint256 k) external view returns (uint256);
    function virtual_price() external view returns (uint256);

    // Fee related
    function fee() external view returns (uint256);
    function mid_fee() external view returns (uint256);
    function out_fee() external view returns (uint256);
    function admin_fee() external view returns (uint256);
    function fee_gamma() external view returns (uint256);
    function future_fee_gamma() external view returns (uint256);

    // Other parameters
    function allowed_extra_profit() external view returns (uint256);
    function adjustment_step() external view returns (uint256);
    function ma_half_time() external view returns (uint256);
    function is_killed() external view returns (bool);

    // Trading function
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);

    // Math contract address (only CurveCryptoNG 2/3-coin pools support)
    function MATH() external view returns (address);
}

interface CurveCryptoMath {
    // newton_y only exists in CryptoMath (v2.x.x), StableMath (v0.x.x) does not have this method
    function newton_y(uint256 ANN, uint256 gamma, uint256[2] calldata x, uint256 D, uint256 i) external view returns (uint256);
}