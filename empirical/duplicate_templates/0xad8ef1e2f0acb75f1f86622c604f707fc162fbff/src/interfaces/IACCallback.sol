// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IACCallback {
    function onOrderSettled(bytes32 traceId, bool success, address token, uint256 amount, bytes calldata data) external;
}
