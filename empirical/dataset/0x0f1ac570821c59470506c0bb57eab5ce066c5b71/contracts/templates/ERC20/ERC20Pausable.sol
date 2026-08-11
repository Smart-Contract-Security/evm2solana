// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

abstract contract ERC20PausableFeature is ERC20Pausable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function pause() external {
        require(_hasRoleFeature(PAUSER_ROLE, msg.sender), "missing PAUSER_ROLE");
        _pause();
    }

    function unpause() external {
        require(_hasRoleFeature(PAUSER_ROLE, msg.sender), "missing PAUSER_ROLE");
        _unpause();
    }

    function _hasRoleFeature(bytes32 role, address account) internal view virtual returns (bool);
}