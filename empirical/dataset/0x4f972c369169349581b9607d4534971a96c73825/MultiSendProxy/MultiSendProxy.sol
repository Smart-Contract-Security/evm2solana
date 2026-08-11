// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MultiSendProxy is ReentrancyGuard {
    uint256 public constant MAX_BATCH_SIZE = 40;

    error EmptyBatch();
    error BatchTooLarge(uint256 maxBatchSize);
    error InvalidOperation(uint8 operation);
    error InvalidTarget();
    error CallFailed(uint256 index);

    /**
     * Encoded transaction format:
     *
     * operation  (1 byte)  => must be 0 (CALL)
     * to         (20 bytes)
     * value      (32 bytes)
     * dataLength (32 bytes)
     * data       (N bytes)
     */
    function multiSend(bytes memory transactions)
        external
        payable
        nonReentrant
    {
        if (transactions.length == 0) {
            revert EmptyBatch();
        }

        uint256 i = 0;
        uint256 txCount = 0;

        while (i < transactions.length) {
            txCount++;

            if (txCount > MAX_BATCH_SIZE) {
                revert BatchTooLarge(MAX_BATCH_SIZE);
            }

            if (transactions.length < i + 85) {
                revert CallFailed(txCount);
            }

            uint8 operation;
            address to;
            uint256 value;
            uint256 dataLength;

            assembly {
                let ptr := add(add(transactions, 0x20), i)

                operation := shr(248, mload(ptr))
                to := shr(96, mload(add(ptr, 0x01)))
                value := mload(add(ptr, 0x15))
                dataLength := mload(add(ptr, 0x35))
            }

            if (operation != 0) {
                revert InvalidOperation(operation);
            }

            if (to == address(0)) {
                revert InvalidTarget();
            }

            uint256 dataStart = i + 85;
            uint256 dataEnd = dataStart + dataLength;

            if (dataEnd > transactions.length) {
                revert CallFailed(txCount);
            }

            bytes memory callData = new bytes(dataLength);

            for (uint256 j = 0; j < dataLength; j++) {
                callData[j] = transactions[dataStart + j];
            }

            (bool success, ) = to.call{value: value}(callData);

            if (!success) {
                revert CallFailed(txCount);
            }

            i = dataEnd;
        }
    }

    receive() external payable {}
}