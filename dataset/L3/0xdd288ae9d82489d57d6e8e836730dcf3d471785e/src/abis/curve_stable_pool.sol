// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface CurveStablePool {
    function N_COINS() external view returns (uint256);
    function coins(uint256) external view returns (address);
    function balances(uint256) external view returns (uint256);
    function initial_A() external view returns (uint256);
    function initial_A_time() external view returns (uint256);
    function future_A() external view returns (uint256);
    function future_A_time() external view returns (uint256);
    function fee() external view returns (uint256);
    function admin_fee() external view returns (uint256);
    function price_oracle() external view returns (uint256);
    function D_oracle() external view returns (uint256);
    function A() external view returns (uint256);
    function A_precise() external view returns (uint256);
    function offpeg_fee_multiplier() external view returns (uint256);
    function get_balances(uint256) external view returns(uint256[] memory balance);
    function stored_rates() external view returns(uint256[] memory rates);
    function admin_balances(uint256) external view returns (uint256);
    function D_ma_time() external view returns(uint256 dTime);
    function oracle() external view returns(address);

}
