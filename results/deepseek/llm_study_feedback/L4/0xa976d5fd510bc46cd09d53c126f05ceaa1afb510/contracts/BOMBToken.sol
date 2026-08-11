// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.16;

import "@openzeppelin-v4/contracts/access/AccessControl.sol";
import "@openzeppelin-v4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-v4/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin-v4/contracts/token/ERC20/extensions/ERC20Votes.sol";

string constant NAME = "Bombie";
string constant SYMBOL = "BOMB";

contract BOMBToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint224 private _maxSupplyValue;

    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        _grantRole(DEFAULT_ADMIN_ROLE, tx.origin);
        _maxSupplyValue = 10_000_000_000 * 1e18;
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(tx.origin, amount);
    }

    function _maxSupply() internal view override returns (uint224) {
        return _maxSupplyValue;
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}