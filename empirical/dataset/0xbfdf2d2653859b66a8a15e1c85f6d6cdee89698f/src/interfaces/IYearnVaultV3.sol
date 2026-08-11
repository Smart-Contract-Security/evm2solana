// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IYearnVaultV3 {
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function profitMaxUnlockTime() external view returns (uint256);
    function strategies(address strategy) external view returns (StrategyParams memory);
    function process_report(address strategy) external returns (uint256 gain, uint256 loss);
    function update_debt(address strategy, uint256 targetDebt, uint256 maxLoss) external returns (uint256);
    function set_profit_max_unlock_time(uint256 newProfitMaxUnlockTime) external;
    function set_auto_allocate(bool autoAllocate) external;
    function set_use_default_queue(bool useDefaultQueue) external;
}
