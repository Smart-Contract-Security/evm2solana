import 'solana';

interface CurveStableFactory {
    function get_decimals(address) external view returns (uint64[] memory);
    function is_meta(address) external view returns (bool);
    function get_coins(address) external view returns (address[] memory);
    function get_n_coins(address) external view returns (uint64);
    function get_pool_asset_types(address) external view returns(uint64[] memory);
    function get_base_pool(address) external view returns(address);
    function get_meta_n_coins(address) external view returns(uint64[2] memory);
    function get_balances(address _pool) external view returns (uint64[] memory);
}