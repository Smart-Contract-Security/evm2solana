// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITrancheBudgetController {
    function executeGovernanceWithdrawal(uint256 trancheId, address recipient, uint256 amount) external;

    function getRiskRemaining(address vault) external view returns (uint256);

    function reserveEngineRisk(address vault, uint256 amount) external;

    function settleEngineRisk(address vault, uint256 reservedRisk, uint256 realizedLoss, uint256 realizedProfit)
        external;
}
