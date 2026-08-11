// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

/// @notice Curve Factory Plain Pool (Vyper 2-coin) - get_balances() returns fixed array, remove_liquidity has 3 params (no claim_admin_fees).
interface ICurvePlainPool {
  function coins(uint256 i) external view returns (address);
  function get_balances() external view returns (uint256[2] memory);

  function totalSupply() external view returns (uint256);
  function get_virtual_price() external view returns (uint256);

  function add_liquidity(
    uint256[2] calldata _amounts,
    uint256 _min_mint_amount,
    address _receiver
  ) external returns (uint256);

  function remove_liquidity(
    uint256 _burn_amount,
    uint256[2] calldata _min_amounts,
    address _receiver
  ) external returns (uint256[2] memory);
}
