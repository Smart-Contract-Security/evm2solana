// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface CurveStableFactory {
    function get_decimals(address) external view returns (uint256[] memory);
    function is_meta(address) external view returns (bool);
    function get_coins(address) external view returns (address[] memory);
    function get_n_coins(address) external view returns (uint256);
    function get_pool_asset_types(address) external view returns(uint256[] memory);
    function get_base_pool(address) external view returns(address);
    function get_meta_n_coins(address) external view returns(uint256[2] memory);
    function get_balances(address _pool) external view returns (uint256[] memory);
}