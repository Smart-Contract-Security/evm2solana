// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/ERC20PresetMinterPauserUpgradeable.sol";
import "contracts/AoABT/blocklist/BlocklistClientUpgradeable.sol";
import "contracts/AoABT/allowlist/AllowlistClientUpgradeable.sol";

contract AoABT is
  ERC20PresetMinterPauserUpgradeable,
  BlocklistClientUpgradeable,
  AllowlistClientUpgradeable
{
  /// @dev Role based access control roles
  bytes32 public constant PRODUCT_ADMIN = keccak256("PRODUCT_ADMIN");

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    string memory name,
    string memory symbol,
    address blocklist,
    address allowlist
  ) public initializer {
    __ERC20PresetMinterPauser_init(name, symbol);
    __BlocklistClientInitializable_init(blocklist);
    __AllowlistClientInitializable_init(allowlist);
  }

  /**
   * @notice Sets the blocklist address
   *
   * @param blocklist New blocklist address
   */
  function setBlocklist(
    address blocklist
  ) external override onlyRole(PRODUCT_ADMIN) {
    _setBlocklist(blocklist);
  }

  /**
   * @notice Sets the allowlist address
   *
   * @param allowlist New allowlist address
   */
  function setAllowlist(
    address allowlist
  ) external override onlyRole(PRODUCT_ADMIN) {
    _setAllowlist(allowlist);
  }


  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    super._beforeTokenTransfer(from, to, amount);

    // Check constraints when `transferFrom` is called to facliitate
    // a transfer between two parties that are not `from` or `to`.
    if (from != msg.sender && to != msg.sender) {
      require(!_isBlocked(msg.sender), "AoABT: 'sender' address blocked");
      require(
        _isAllowed(msg.sender),
        "AoABT: 'sender' address not on allowlist"
      );
    }

    if (from != address(0)) {
      // If not minting
      require(!_isBlocked(from), "AoABT: 'from' address blocked");
      require(_isAllowed(from), "AoABT: 'from' address not on allowlist");
    }

    if (to != address(0)) {
      // If not burning
      require(!_isBlocked(to), "AoABT: 'to' address blocked");
      require(_isAllowed(to), "AoABT: 'to' address not on allowlist");
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
