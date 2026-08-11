// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract RoleBasedToken is ERC20, Ownable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bool private _paused;

    event TokensPaused(address indexed by);
    event TokensUnpaused(address indexed by);

    modifier whenNotPaused() {
        require(!_paused, "RoleBasedToken: token transfer while paused");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply * 10 ** decimals());
        }

        _paused = false;
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(to != address(0), "RoleBasedToken: cannot mint to zero address");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
        require(from != address(0), "RoleBasedToken: cannot burn from zero address");
        _burn(from, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyRole(BURNER_ROLE) {
        require(account != address(0), "RoleBasedToken: cannot burn from zero address");
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "RoleBasedToken: insufficient allowance");
        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        require(!_paused, "RoleBasedToken: token already paused");
        _paused = true;
        emit TokensPaused(msg.sender);
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        require(_paused, "RoleBasedToken: token not paused");
        _paused = false;
        emit TokensUnpaused(msg.sender);
    }

    function isPaused() public view returns (bool) {
        return _paused;
    }

    function grantRole(bytes32 role, address account) public override onlyRole(ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public override onlyRole(ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "RoleBasedToken: new owner cannot be zero address");
        address oldOwner = owner();
        _transferOwnership(newOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(ADMIN_ROLE, newOwner);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
        _revokeRole(ADMIN_ROLE, oldOwner);
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._update(from, to, amount);
    }

}
