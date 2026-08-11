import 'solana';

interface IFeeManager {
    function startAccrual() external;
    function setFeeConfig(
        uint64 annualBps,
        uint64 performanceBps,
        uint64 hurdleBps_,
        uint64 totalAssetsValue,
        uint64 effectiveSupply
    ) external returns (uint64 managementFeeShares);
    function accrueManagementFee(uint64 totalAssetsValue, uint64 effectiveSupply) external returns (uint64 shares);
    function claimManagementFee() external returns (uint64 shares);
    function claimPerformanceFee() external returns (uint64 shares);
    function claimAllFees() external returns (uint64 shares);
    function previewPerformanceFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        view
        returns (uint64 currentSharePrice, uint64 threshold, uint64 feeShares);
    function settlePerformanceFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        returns (uint64 shares, uint64 newHighWaterMark);
    function uncollectedFeeInShares() external view returns (uint64);
    function unclaimedManagementFeeShares() external view returns (uint64);
    function claimedManagementFeeShares() external view returns (uint64);
    function unclaimedPerformanceFeeShares() external view returns (uint64);
    function claimedPerformanceFeeShares() external view returns (uint64);
    function effectiveTotalSupply(uint64 totalSupply) external view returns (uint64);
}