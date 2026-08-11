import 'solana';

@program_id("GateCoin111111111111111111111111111111111111")
interface IGateCoin {
    function spinReward(address wallet) external pure returns (uint64);
    function balanceOf(address wallet) external view returns (uint64);
}