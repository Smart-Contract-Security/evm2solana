// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "./IERC20.sol";

/// @notice Flash-loan recipient called by Balancer V2 Vault.
/// @dev Selector-compatible with Balancer V2 mainnet vault
/// (0xBA12222222228d8Ba445958a75a0704d566BF2C8). Local `IERC20` is structurally
/// interchangeable with the canonical Balancer interface at the ABI layer.
interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external;
}

/// @notice Minimal subset of Balancer V2 Vault — fallback flash-loan source
/// when Fira's own market is thin on the required loan token.
interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
}
