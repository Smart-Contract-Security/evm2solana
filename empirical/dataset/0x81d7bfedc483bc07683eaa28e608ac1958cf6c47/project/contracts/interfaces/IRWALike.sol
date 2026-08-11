// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

// This interface is not inherited directly by RWA, instead, it is a
// subset of functions provided by all RWA tokens that the RWA Hub
// Client uses.
import "contracts/external/openzeppelin/contracts/token/IERC20.sol";

/**
 * @title IRWALike
 * @notice Interface for Real World Asset (RWA) tokens that extend the ERC20 standard.
 * @dev This interface includes functions for minting and burning tokens.
 */
interface IRWALike is IERC20 {
  /**
   * @notice Mints new tokens and assigns them to a specific address.
   * @dev This function allows the creation of new tokens, increasing the total supply.
   * @param to The address to which the newly minted tokens will be assigned.
   * @param amount The number of tokens to mint.
   */
  function mint(address to, uint256 amount) external;

  /**
   * @notice Burns a specified amount of tokens from the caller's account.
   * @dev This function decreases the total supply by burning tokens from the caller's balance.
   * @param amount The number of tokens to burn.
   */
  function burn(uint256 amount) external;

  /**
   * @notice Burns a specified amount of tokens from a particular account.
   * @dev This function allows burning tokens from another address's account, typically used for reducing the supply.
   * @param from The address from which the tokens will be burned.
   * @param amount The number of tokens to burn.
   */
  function burnFrom(address from, uint256 amount) external;
}
