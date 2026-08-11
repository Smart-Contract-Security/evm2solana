// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "contracts/interfaces/IBlocklist.sol";

/**
 * @title Blocklist
 * @author Asseto Finance
 * @notice This contract manages the blocklist status for accounts.
 */
contract Blocklist is AccessControlEnumerable, IBlocklist {

  constructor(address admin) {
    if (admin == address(0)) {
      revert BlocklistAdminCannotBeZero();
    }
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(KYC_ADMIN, admin);
  }

  // {<address> => is account blocked}
  mapping(address => bool) private blockedAddresses;

  /// @dev Role based access control roles
  bytes32 public constant KYC_ADMIN = keccak256("KYC_ADMIN");

  /**
   * @notice Returns name of contract
   */
  function name() external pure returns (string memory) {
    return "Blocklist Oracle";
  }

  /**
   * @notice Function to add a list of accounts to the blocklist
   *
   * @param accounts Array of addresses to block
   */
  function addToBlocklist(address[] calldata accounts) external onlyRole(KYC_ADMIN) {
    require(accounts.length > 0, "accounts array cannot be empty");
    for (uint256 i; i < accounts.length;) {
      if (accounts[i] == address(0)) {
        revert BlocklistUserCannotBeZero();
      }
      blockedAddresses[accounts[i]] = true;
      unchecked{
        ++i;
      }
    }
    emit BlockedAddressesAdded(accounts);
  }

  /**
   * @notice Function to remove a list of accounts from the blocklist
   *
   * @param accounts Array of addresses to unblock
   */
  function removeFromBlocklist(address[] calldata accounts) external onlyRole(KYC_ADMIN) {
    require(accounts.length > 0, "accounts array cannot be empty");
    for (uint256 i; i < accounts.length; ++i) {
      if (accounts[i] == address(0)) {
        revert BlocklistUserCannotBeZero();
      }
      blockedAddresses[accounts[i]] = false;
    }
    emit BlockedAddressesRemoved(accounts);
  }

  /**
   * @notice Function to check if an account is blocked
   *
   * @param addr Address to check
   *
   * @return True if account is blocked, false otherwise
   */
  function isBlocked(address addr) external view returns (bool) {
    return blockedAddresses[addr];
  }
}
