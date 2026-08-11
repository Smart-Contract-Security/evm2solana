// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPoolVault {
    function asset() external view returns (address);

    function budgetController() external view returns (address);

    function businessController() external view returns (address);

    function totalAssets() external view returns (uint256);

    function custodiedAssets() external view returns (uint256);

    function businessEscrowAssets() external view returns (uint256);

    function reservedBusinessPayout() external view returns (uint256);

    function unallocatedClaimableAssets() external view returns (uint256);

    function totalClaimableAssets() external view returns (uint256);

    function claimableAssets(address account) external view returns (uint256);

    function activeBusinessRoundCount() external view returns (uint256);

    function openBusinessRound() external;

    function closeBusinessRound() external;

    function receiveBusinessEth(uint256 amount, uint256 reservedPayoutAmount) external payable;

    function receiveBusinessAssetFrom(address payer, uint256 amount, uint256 reservedPayoutAmount) external;

    function increaseBusinessPayoutReserve(uint256 additionalReservedPayout) external;

    function businessPayout(
        address recipient,
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    ) external;

    function settleBusinessPayoutPool(
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    ) external;

    function refundBusinessPayoutPool(
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    ) external;

    function allocateBusinessPayout(address recipient, uint256 amount) external;

    function claimBusinessPayout(address receiver, uint256 amount) external;

    function allocateAndClaimBusinessPayout(
        address recipient,
        address receiver,
        uint256 amount
    ) external;

    function withdrawByBudget(address recipient, uint256 amount) external;
}
