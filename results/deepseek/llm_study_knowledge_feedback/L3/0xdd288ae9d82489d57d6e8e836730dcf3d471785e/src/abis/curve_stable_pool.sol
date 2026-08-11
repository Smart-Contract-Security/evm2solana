import 'solana';

interface CurveStablePool {
    function N_COINS() external view returns (uint64);
    function coins(uint64) external view returns (address);
    function balances(uint64) external view returns (uint64);
    function initial_A() external view returns (uint64);
    function initial_A_time() external view returns (uint64);
    function future_A() external view returns (uint64);
    function future_A_time() external view returns (uint64);
    function fee() external view returns (uint64);
    function admin_fee() external view returns (uint64);
    function price_oracle() external view returns (uint64);
    function D_oracle() external view returns (uint64);
    function A() external view returns (uint64);
    function A_precise() external view returns (uint64);
    function offpeg_fee_multiplier() external view returns (uint64);
    function get_balances(uint64) external view returns(uint64[] memory balance);
    function stored_rates() external view returns(uint64[] memory rates);
    function admin_balances(uint64) external view returns (uint64);
    function D_ma_time() external view returns(uint64 dTime);
    function oracle() external view returns(address);
}