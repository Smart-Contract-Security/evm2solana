// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal surface of `vendor_cobo_nav_fund/evm/src/Fund/CoboFundToken.sol` required by AgentRouter.
/// @dev Aligns with Cobo enum order: Pending, Rejected, Executed.
interface ICoboFundToken is IERC20 {
    enum RedemptionStatus {
        Pending,
        Rejected,
        Executed
    }

    struct RedemptionRequest {
        uint256 id;
        address user;
        uint256 assetAmount;
        uint256 shareAmount;
        uint256 requestedAt;
        RedemptionStatus status;
    }

    /// @notice Cobo `redemptions` public array auto-getter.
    function redemptions(uint256 reqId)
        external
        view
        returns (
            uint256 id,
            address user,
            uint256 assetAmount,
            uint256 shareAmount,
            uint256 requestedAt,
            RedemptionStatus status
        );

    function mint(uint256 assetAmount) external returns (uint256 shareAmount);

    function requestRedemption(uint256 shareAmount) external returns (uint256 reqId);
}
