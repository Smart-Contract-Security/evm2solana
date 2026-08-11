// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/external/openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

contract TokenProxy is TransparentUpgradeableProxy {
  constructor(
    address _logic,
    address _admin,
    bytes memory _data
  ) TransparentUpgradeableProxy(_logic, _admin, _data) {}

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
