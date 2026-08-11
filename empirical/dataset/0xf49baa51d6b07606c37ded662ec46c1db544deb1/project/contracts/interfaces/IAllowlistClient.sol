// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/interfaces/IAllowlist.sol";

/**
 * @title IAllowlistClient
 * @author Asseto Finance
 * @notice The client interface for Asseto's Allowlist contract.
 */
interface IAllowlistClient {
  /**
   * @notice Returns the reference to the allowlist contract that this client queries.
   *
   * @return IAllowlist The address of the allowlist contract.
   */
  function allowlist() external view returns (IAllowlist);

  /**
   * @notice Sets the allowlist contract reference.
   *
   * @param allowlist The address of the new allowlist contract to be set.
   */
  function setAllowlist(address allowlist) external;

  /**
   * @dev Event for when the allowlist reference is set
   *
   * @param oldAllowlist The old allowlist
   * @param newAllowlist The new allowlist
   */
  event AllowlistSet(address oldAllowlist, address newAllowlist);

  /**
   * @notice Error raised when the caller attempts to set the allowlist reference
   *         to the zero address.
   */
  error AllowlistZeroAddress();

  /**
  * @notice Error thrown when attempting to perform an action on a not a allowlist account.
  */
  error NotAllowlistAccount();
}
