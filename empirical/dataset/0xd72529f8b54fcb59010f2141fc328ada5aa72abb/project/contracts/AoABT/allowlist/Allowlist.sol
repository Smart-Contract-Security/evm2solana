// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "contracts/interfaces/IAllowlist.sol";


/**
 * @title Allowlist
 * @author Asseto Finance
 * @notice This contract manages the allowlist status for accounts.
 */
contract Allowlist is AccessControlEnumerable, IAllowlist {

  constructor(address admin) {
    if (admin == address(0)) {
      revert AllowlistAdminCannotBeZero();
    }
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(KYC_ADMIN, admin);
  }

  // {<address> => is account allowed}
  mapping(address => bool) private allowedAddresses;

  /// @dev Role based access control roles
  bytes32 public constant KYC_ADMIN = keccak256("KYC_ADMIN");

  /**
   * @notice Returns name of contract
   */
  function name() external pure returns (string memory) {
    return "Allowlist Oracle";
  }

  /**
   * @notice Function to add a list of accounts to the allowlist
   *
   * @param accounts Array of addresses to allow
   */
  function addToAllowlist(address[] calldata accounts) external onlyRole(KYC_ADMIN) {
    require(accounts.length > 0, "accounts array cannot be empty");
    for (uint256 i; i < accounts.length;) {
      if (accounts[i] == address(0)) {
        revert AllowlistUserCannotBeZero();
      }
      allowedAddresses[accounts[i]] = true;
      unchecked{
        ++i;
      }
    }
    emit AllowedAddressesAdded(accounts);
  }

  /**
   * @notice Function to remove a list of accounts from the allowlist
   *
   * @param accounts Array of addresses to unallow
   */
  function removeFromAllowlist(address[] calldata accounts) external onlyRole(KYC_ADMIN) {
    require(accounts.length > 0, "accounts array cannot be empty");
    for (uint256 i; i < accounts.length; ++i) {
      if (accounts[i] == address(0)) {
        revert AllowlistUserCannotBeZero();
      }
      allowedAddresses[accounts[i]] = false;
    }
    emit AllowedAddressesRemoved(accounts);
  }

  /**
   * @notice Function to check if an account is allowed
   *
   * @param addr Address to check
   *
   * @return True if account is allowed, false otherwise
   */
  function isAllowed(address addr) external view returns (bool) {
    return allowedAddresses[addr];
  }
}
