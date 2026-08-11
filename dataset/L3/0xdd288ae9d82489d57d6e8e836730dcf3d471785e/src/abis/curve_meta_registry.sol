// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface CurveMetaRegistry {
    // Registry and handler related
    function get_registry_handlers_from_pool(address _pool) external view returns (address[10] memory);
    function get_base_registry(address registry_handler) external view returns (address);
    function get_base_pool(address pool) external view returns (address);

    // Pool registration
    function is_registered(address _pool) external view returns (bool);
    function is_registered(address _pool, uint256 _handler_id) external view returns (bool);
    
    // Pool count and list
    function pool_count() external view returns (uint256);
    function pool_list(uint256 _index) external view returns (address);
    
    // Coin information
    function get_n_coins(address _pool) external view returns (uint256);
    function get_n_coins(address _pool, uint256 _handler_id) external view returns (uint256);
    function get_coins(address _pool) external view returns (address[8] memory);
    function get_coins(address _pool, uint256 _handler_id) external view returns (address[8] memory);
    function get_decimals(address _pool) external view returns (uint256[8] memory);
    function get_decimals(address _pool, uint256 _handler_id) external view returns (uint256[8] memory);
    
    // Balance information
    function get_balances(address _pool) external view returns (uint256[8] memory);
    function get_balances(address _pool, uint256 _handler_id) external view returns (uint256[8] memory);
    function get_admin_balances(address _pool) external view returns (uint256[8] memory);
    function get_admin_balances(address _pool, uint256 _handler_id) external view returns (uint256[8] memory);
    
    // Underlying coins (for meta pools)
    function get_underlying_coins(address _pool) external view returns (address[8] memory);
    function get_underlying_coins(address _pool, uint256 _handler_id) external view returns (address[8] memory);
    function get_underlying_decimals(address _pool) external view returns (uint256[8] memory);
    function get_underlying_decimals(address _pool, uint256 _handler_id) external view returns (uint256[8] memory);
    function get_underlying_balances(address _pool) external view returns (uint256[8] memory);
    function get_underlying_balances(address _pool, uint256 _handler_id) external view returns (uint256[8] memory);
    
    // Pool metadata
    function is_meta(address _pool) external view returns (bool);
    function is_meta(address _pool, uint256 _handler_id) external view returns (bool);
    function get_pool_name(address _pool) external view returns (string memory);
    function get_pool_name(address _pool, uint256 _handler_id) external view returns (string memory);
    function get_pool_asset_type(address _pool) external view returns (uint256);
    function get_pool_asset_type(address _pool, uint256 _handler_id) external view returns (uint256);
    
    // LP token
    function get_lp_token(address _pool) external view returns (address);
    function get_lp_token(address _pool, uint256 _handler_id) external view returns (address);
    
    // Pool parameters and fees
    function get_pool_params(address _pool) external view returns (uint256[20] memory);
    function get_pool_params(address _pool, uint256 _handler_id) external view returns (uint256[20] memory);
    function get_fees(address _pool) external view returns (uint256[10] memory);
    function get_fees(address _pool, uint256 _handler_id) external view returns (uint256[10] memory);
}
