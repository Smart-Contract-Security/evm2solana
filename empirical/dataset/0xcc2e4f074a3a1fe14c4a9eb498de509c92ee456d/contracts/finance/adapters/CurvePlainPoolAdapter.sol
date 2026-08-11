// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../interfaces/IOperoseAdapter.sol";
import "../interfaces/curve/ICurvePlainPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Adapter for Curve Factory Plain Pool (Vyper 2-coin): get_balances() returns uint256[2], rate_multipliers(i), remove_liquidity(3 params).
contract CurvePlainPoolAdapter is IOperoseAdapter {
  using SafeERC20 for IERC20;

  uint256 private constant N = 2;

  function getBaseTokens(address defiToken) public view returns (address[] memory tokens) {
    tokens = new address[](N);
    tokens[0] = ICurvePlainPool(defiToken).coins(0);
    tokens[1] = ICurvePlainPool(defiToken).coins(1);
  }

  function getBaseRatios(address defiToken) external view returns (uint256[] memory ratios) {
    uint256[2] memory balances = ICurvePlainPool(defiToken).get_balances();
    uint256 total = balances[0] + balances[1];
    ratios = new uint256[](N);
    if (total == 0) return ratios;
    ratios[0] = (balances[0] * 1e18) / total;
    ratios[1] = (balances[1] * 1e18) / total;
  }

  function getBaseAmounts(address defiToken, uint256 defiAmount) external view returns (uint256[] memory baseAmounts) {
    uint256 totalSupply = ICurvePlainPool(defiToken).totalSupply();
    uint256[2] memory balances = ICurvePlainPool(defiToken).get_balances();
    baseAmounts = new uint256[](N);
    baseAmounts[0] = (balances[0] * defiAmount) / totalSupply;
    baseAmounts[1] = (balances[1] * defiAmount) / totalSupply;
  }

  function getGrowthIndex(address defiToken) external view returns (uint256 index) {
    return ICurvePlainPool(defiToken).get_virtual_price();
  }

  function zapIn(address defiToken, uint256[] memory baseAmounts) external {
    address[] memory tokens = getBaseTokens(defiToken);
    for (uint256 i = 0; i < N; ++i) {
      if (IERC20(tokens[i]).allowance(address(this), defiToken) < baseAmounts[i]) {
        SafeERC20.forceApprove(IERC20(tokens[i]), defiToken, type(uint256).max);
      }
    }
    uint256[2] memory amounts;
    amounts[0] = baseAmounts[0];
    amounts[1] = baseAmounts[1];
    ICurvePlainPool(defiToken).add_liquidity(amounts, 0, address(this));
  }

  function zapOut(address defiToken, uint256 defiAmount) external {
    if (IERC20(defiToken).allowance(address(this), defiToken) < defiAmount) {
      SafeERC20.forceApprove(IERC20(defiToken), defiToken, type(uint256).max);
    }
    uint256[2] memory minAmounts;
    ICurvePlainPool(defiToken).remove_liquidity(defiAmount, minAmounts, address(this));
  }
}
