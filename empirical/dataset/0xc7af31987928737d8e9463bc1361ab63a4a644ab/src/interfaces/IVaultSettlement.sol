// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVaultSettlement {
    function settleDeposit(
        bytes32 groupId,
        uint256 reqId,
        address[] calldata etfTokens,
        uint256[] calldata amounts,
        uint256 refundUsdc,
        uint256 navRound
    ) external;

    function settleRedeem(bytes32 groupId, uint256 reqId, uint256 usdcReceived, uint256 navRound)
        external;
    function settleRebalance(bytes32 rbId, address[] calldata tokens, uint256[] calldata amounts)
        external;
    function settleRebalanceFailure(bytes32 rbId, bytes calldata reason) external;
    function settleFailure(bytes32 groupId, uint256 reqId, uint256 returnedUsdc, bytes calldata reason)
        external;
}
