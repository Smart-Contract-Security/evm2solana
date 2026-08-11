import 'solana';

interface CurveCryptoPool {
    function token() external view returns (address);
    function coins(uint64 i) external view returns (address);
    function balances(uint64 i) external view returns (uint64);
    
    function A() external view returns (uint64);
    function gamma() external view returns (uint64);
    function D() external view returns (uint64);
    
    function initial_A_gamma() external view returns (uint64);
    function future_A_gamma() external view returns (uint64);
    function initial_A_gamma_time() external view returns (uint64);
    function future_A_gamma_time() external view returns (uint64);
    
    function price_scale() external view returns (uint64);
    function price_scale(uint64 k) external view returns (uint64);
    function price_oracle(uint64 k) external view returns (uint64);
    function virtual_price() external view returns (uint64);
    
    function fee() external view returns (uint64);
    function mid_fee() external view returns (uint64);
    function out_fee() external view returns (uint64);
    function admin_fee() external view returns (uint64);
    function fee_gamma() external view returns (uint64);
    function future_fee_gamma() external view returns (uint64);

    function allowed_extra_profit() external view returns (uint64);
    function adjustment_step() external view returns (uint64);
    function ma_half_time() external view returns (uint64);
    function is_killed() external view returns (bool);

    function get_dy(uint64 i, uint64 j, uint64 dx) external view returns (uint64);

    function MATH() external view returns (address);
}

interface CurveCryptoMath {
    function newton_y(uint64 ANN, uint64 gamma, uint64[2] calldata x, uint64 D, uint64 i) external view returns (uint64);
}