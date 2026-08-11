// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract dKZT is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AUTOMATION_SAFE_ROLE = keccak256("AUTOMATION_SAFE_ROLE");

    error DailyMintLimitExceeded(uint256 spent, uint256 limit, uint256 amount);
    error DailyBurnLimitExceeded(uint256 spent, uint256 limit, uint256 amount);
    error DailyLimitNotSet();

    uint8 private _decimal;

    uint256 public dailyLimitMint;
    uint256 public dailyLimitBurn;
    uint256 public spentMintToday;
    uint256 public spentBurnToday;
    uint256 public currentDayIndex;

    event AutomationDailyLimitsUpdated(uint256 mintLimit, uint256 burnLimit);
    event AutoMint(address indexed to, uint256 amount);
    event AutoBurn(address indexed from, uint256 amount);
    event AutoBurnFrom(address indexed from, address indexed account, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        uint8 decimal,
        address treasurySafe,
        address automationSafe,
        address pauser
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init(name);

        _decimal = decimal;

        _grantRole(DEFAULT_ADMIN_ROLE, treasurySafe);
        _grantRole(MINTER_ROLE, treasurySafe);
        _grantRole(AUTOMATION_SAFE_ROLE, automationSafe);
        _grantRole(PAUSER_ROLE, pauser);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 amount) public override onlyRole(MINTER_ROLE) {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyRole(MINTER_ROLE) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function setAutomationDailyLimits(uint256 mintLimit, uint256 burnLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        dailyLimitMint = mintLimit;
        dailyLimitBurn = burnLimit;
        emit AutomationDailyLimitsUpdated(mintLimit, burnLimit);
    }

    function autoMint(address to, uint256 amount) public onlyRole(AUTOMATION_SAFE_ROLE) {
        _checkAndUpdateDailyLimit(true, amount);
        _mint(to, amount);
        emit AutoMint(to, amount);
    }

    function autoBurn(uint256 amount) public onlyRole(AUTOMATION_SAFE_ROLE) {
        _checkAndUpdateDailyLimit(false, amount);
        _burn(_msgSender(), amount);
        emit AutoBurn(_msgSender(), amount);
    }

    function autoBurnFrom(address from, uint256 amount) public onlyRole(AUTOMATION_SAFE_ROLE) {
        _checkAndUpdateDailyLimit(false, amount);
        _spendAllowance(from, _msgSender(), amount);
        _burn(from, amount);
        emit AutoBurnFrom(from, msg.sender, amount);
    }

    function _checkAndUpdateDailyLimit(bool isMint, uint256 amount) internal {
        uint256 currentDay = block.timestamp / 1 days;

        if (currentDay != currentDayIndex) {
            currentDayIndex = currentDay;
            spentMintToday = 0;
            spentBurnToday = 0;
        }

        if (isMint) {
            if (dailyLimitMint == 0) {
                revert DailyLimitNotSet();
            }
            if (spentMintToday + amount > dailyLimitMint) {
                revert DailyMintLimitExceeded(spentMintToday, dailyLimitMint, amount);
            }
            spentMintToday += amount;
        } else {
            if (dailyLimitBurn == 0) {
                revert DailyLimitNotSet();
            }
            if (spentBurnToday + amount > dailyLimitBurn) {
                revert DailyBurnLimitExceeded(spentBurnToday, dailyLimitBurn, amount);
            }
            spentBurnToday += amount;
        }
    }

    function decimals() public view override returns (uint8) {
        return _decimal;
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
