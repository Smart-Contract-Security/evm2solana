// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract GOLD is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public transferFee;
    uint256 public mintBurnFee;
    mapping(address => bool) private whitelist;
    address public treasury;

    event AddedToWhitelist(address[] accounts);
    event RemovedFromWhitelist(address[] accounts);
    event SetTreasury(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address[] calldata _whiteList, address _treasury) initializer public {
        __ERC20_init("100% Backed Physical Gold Test", "tGOLD");
        __ERC20Permit_init("tGOLD");
        __AccessControl_init();
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        __UUPSUpgradeable_init();
        transferFee = 12;
        for (uint256 i = 0; i < _whiteList.length; i++) {
            whitelist[_whiteList[i]] = true;
        }
        treasury = _treasury;
        emit AddedToWhitelist(_whiteList);
        emit SetTreasury(_treasury);
    }

    // calculate transfer amount
    function calcAmount(uint256 amount, uint256 fee) pure  private returns (uint256) {
        return amount * (10000 - fee) / 10000;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address from = _msgSender();
        if (isWhitelisted(from) || isWhitelisted(to)) {
            _transfer(from, to, value);
        }
        else {
            uint256 tAmount = calcAmount(value, transferFee);
            _transfer(from, treasury, value - tAmount);
            _transfer(from, to, tAmount);
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        if (isWhitelisted(from) || isWhitelisted(to)) {
            _transfer(from, to, value);
        } else {
            uint256 tAmount = calcAmount(value, transferFee);
            _transfer(from, treasury, value - tAmount);
            _transfer(from, to, tAmount);
        }
        return true;
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if (isWhitelisted(to)) {
            _mint(to, amount);
        } else {
            uint256 mAmount = calcAmount(amount, mintBurnFee);
            _mint(treasury, amount - mAmount);
            _mint(to, mAmount);
        }
    }

    function burn(uint256 value) public {
        address from = _msgSender();
        if (isWhitelisted(from)) {
            _burn(from, value);
        } else {
            uint256 bAmount = calcAmount(value, mintBurnFee);
            _transfer(from, treasury, value - bAmount);
            _burn(from, bAmount);
        }
    }
    
    function burnFrom(address account, uint256 value) public {
        _spendAllowance(account, _msgSender(), value);
        if (isWhitelisted(account)) {
            _burn(account, value);
        } else {
            uint256 bAmount = calcAmount(value, mintBurnFee);
            _transfer(account, treasury, value - bAmount);
            _burn(account, bAmount);
        }
    }

    // Function to add an address to the whitelist for sending
    function addToWhitelist(address[] calldata _addresses) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = true;
        }
        emit AddedToWhitelist(_addresses);
    }

    // Function to remove an address from the whitelist for sending
    function removeFromWhitelist(address[] calldata _addresses) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = false;
        }
        emit RemovedFromWhitelist(_addresses);
    }

    // Function to check if an address is whitelisted
    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }

    function setTreasury(address _treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    function updateFees(uint256 _transferFee, uint256 _mintBurnFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        transferFee = _transferFee;
        mintBurnFee = _mintBurnFee;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}
}
