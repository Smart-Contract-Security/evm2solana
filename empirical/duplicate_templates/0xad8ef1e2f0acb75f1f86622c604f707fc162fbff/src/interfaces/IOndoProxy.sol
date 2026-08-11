// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOndoProxy {
    struct DepositIntent {
        address receiver;
        address outputToken;
        uint256 destinationChainId;
        uint256 maxSlippageBps;
        uint256 maxLossPercentBps;
        bytes extraData;
    }

    function depositERC20FromRecipient(
        address token,
        uint256 amount,
        bytes32 traceId,
        DepositIntent calldata intent
    ) external;

}
