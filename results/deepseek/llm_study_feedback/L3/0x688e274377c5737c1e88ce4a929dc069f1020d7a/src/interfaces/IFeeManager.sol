// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'solana';

interface IFeeManager {
    function startAccrual() external;
    function setFeeConfig(
        uint256 annualBps,
        uint256 performanceBps,
        uint256 hurdleBps_,
        uint256 totalAssetsValue,
        uint256 effectiveSupply
    ) external returns (uint256 managementFeeShares);
    function accrueManagementFee(uint256 totalAssetsValue, uint256 effectiveSupply) external returns (uint256 shares);
    function claimManagementFee() external returns (uint256 shares);
    function claimPerformanceFee() external returns (uint256 shares);
    function claimAllFees() external returns (uint256 shares);
    function previewPerformanceFee(uint256 totalAssetsValue, uint256 effectiveSupply)
        external
        view
        returns (uint256 currentSharePrice, uint256 threshold, uint256 feeShares);
    function settlePerformanceFee(uint256 totalAssetsValue, uint256 effectiveSupply)
        external
        returns (uint256 shares, uint256 newHighWaterMark);
    function uncollectedFeeInShares() external view returns (uint256);
    function unclaimedManagementFeeShares() external view returns (uint256);
    function claimedManagementFeeShares() external view returns (uint256);
    function unclaimedPerformanceFeeShares() external view returns (uint256);
    function claimedPerformanceFeeShares() external view returns (uint256);
    function effectiveTotalSupply(uint256 totalSupply) external view returns (uint256);
}