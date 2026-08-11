@program_id("StakingAmounts111111111111111111111111111")
interface IStakingAmounts {
    function stakedOf(address _user) external view returns (uint64);

    function totalStaked() external view returns (uint64);
}