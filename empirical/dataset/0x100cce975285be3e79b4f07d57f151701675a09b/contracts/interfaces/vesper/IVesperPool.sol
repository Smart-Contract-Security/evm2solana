// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IVesperPool is IERC20Metadata {
    function creditLimit(address strategy_) external view returns (uint256);

    function deposit(uint256 collateralAmount_) external;

    function excessDebt(address strategy_) external view returns (uint256);

    function governor() external view returns (address);

    function poolAccountant() external view returns (address);

    function poolRewards() external view returns (address);

    function pricePerShare() external view returns (uint256);

    function reportEarning(uint256 profit_, uint256 loss_, uint256 payback_) external;

    function repayDebt(uint256 amount_) external;

    function strategy(
        address strategy_
    )
        external
        view
        returns (
            bool _active,
            uint256 _interestFee,
            uint256 _debtRate,
            uint256 _lastRebalance,
            uint256 _totalDebt,
            uint256 _totalLoss,
            uint256 _totalProfit,
            uint256 _debtRatio,
            uint256 _externalDepositFee
        );

    function token() external view returns (IERC20);

    function tokensHere() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function totalDebtOf(address strategy_) external view returns (uint256);

    function totalDebtRatio() external view returns (uint256);

    function totalValue() external view returns (uint256);

    function withdraw(uint256 share_) external;
}
