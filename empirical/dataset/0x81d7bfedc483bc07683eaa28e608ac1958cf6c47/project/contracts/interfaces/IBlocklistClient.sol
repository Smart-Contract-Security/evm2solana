// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/interfaces/IBlocklist.sol";

/**
 * @title IBlocklistClient
 * @author Asseto Finance
 * @notice The client interface for the Blocklist contract.
 */
interface IBlocklistClient {
  /**
   * @notice Returns the blocklist that this client queries.
   * @dev Provides access to the current blocklist contract reference.
   * @return The address of the blocklist contract.
   */
  function blocklist() external view returns (IBlocklist);

  /**
   * @notice Sets the blocklist reference.
   * @dev Allows the contract owner or authorized entity to update the blocklist contract address.
   * @param registry The address of the new blocklist contract.
   */
  function setBlocklist(address registry) external;

  /**
   * @notice Error thrown when attempting to set the blocklist reference to the zero address.
   */
  error BlocklistZeroAddress();

  /**
   * @notice Error thrown when attempting to perform an action on a blocked account.
   */
  error BlockedAccount();

  /**
   * @dev Event emitted when the blocklist reference is updated.
   * @param oldBlocklist The previous blocklist contract address.
   * @param newBlocklist The new blocklist contract address.
   */
  event BlocklistSet(address oldBlocklist, address newBlocklist);
}
