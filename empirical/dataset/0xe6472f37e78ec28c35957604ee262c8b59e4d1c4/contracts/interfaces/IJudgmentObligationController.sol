// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IJudgmentObligationController {
    function poolVault() external view returns (address);

    function asset() external view returns (address);

    function openRoundCapacity(
        uint256 roundId
    ) external returns (uint256 capacity);

    function commitJudgmentEth(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxReservedPayout
    ) external payable;

    function commitJudgmentFromWallet(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxReservedPayout
    ) external;

    function commitAggregateJudgmentEth(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxPayoutAmount
    ) external payable;

    function commitAggregateJudgmentFromWallet(
        uint256 roundId,
        uint256 judgmentId,
        address owner,
        uint256 entryAmount,
        uint256 maxPayoutAmount
    ) external;

    function settleJudgment(uint256 judgmentId, uint256 payoutAmount) external;

    function settleRoundPayoutPool(
        uint256 roundId,
        uint256 totalPayoutAmount
    ) external;

    function allocateSettledJudgmentPayout(
        uint256 judgmentId,
        uint256 payoutAmount
    ) external;

    function allocateAndClaimSettledJudgmentPayout(
        uint256 judgmentId,
        uint256 payoutAmount,
        address receiver
    ) external;

    function increaseReservedPayout(
        uint256 judgmentId,
        uint256 newMaxReservedPayout
    ) external;

    function increaseRoundReservedPayout(
        uint256 roundId,
        uint256 additionalReservedPayout
    ) external;

    function closeRound(uint256 roundId) external;
}
