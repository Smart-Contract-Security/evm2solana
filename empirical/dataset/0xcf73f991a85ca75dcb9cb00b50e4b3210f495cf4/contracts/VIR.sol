// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/**
 * @dev Upgradeable ERC20 token with role-based minting, pausing, account freezing, permit support,
 * and controlled implementation upgrades. The proxy initializer can be executed only once.
 *
 * @custom:security-contact bugs@ripple.com
 */
contract VIR is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ERC20PausableUpgradeable, ERC20PermitUpgradeable {
    // keccak256("MINTER")
    bytes32 constant public MINTER_ROLE = 0xf0887ba65ee2024ea881d91b74c2450ef19e1557f03bed3ea9f16b037cbe2dc9;
    // keccak256("UPGRADER")
    bytes32 constant public UPGRADER_ROLE = 0xa615a8afb6fffcb8c6809ac0997b5c9c12b8cc97651150f14c8f6203168cff4c;
    // keccak256("PAUSER")
    bytes32 constant public PAUSER_ROLE = 0x539440820030c4994db4e31b6b800deafd503688728f932addfe7a410515c14c;
    // keccak256("BURNER")
    bytes32 constant public BURNER_ROLE = 0x9667e80708b6eeeb0053fa0cca44e028ff548e2a9f029edfeac87c118b08b7c8;
    // keccak256("BURN_ON_BEHALF")
    bytes32 constant public BURN_ON_BEHALF_ROLE = 0xe3b63b0f35a3b6dc274acaf81c213a3b3a5387941c86749ceba4024b87a0640a;

    mapping(address account => bool) private _frozenAccounts;

    /**
     * Emitted when an account is frozen.
     */
    event AccountFrozen(address account);

    /**
     * Emitted when an account is unfrozen.
     */
    event AccountUnfrozen(address account);

    /// @dev Reverts when an action requires an active (non-frozen) `account`.
    error AccountIsFrozen(address account);

    /// @dev Reverts when an action requires a frozen `account`.
    error AccountIsNotFrozen(address account);

    /// @dev Reverts when `freezeAccounts` is called with an empty array.
    error NoAccountsToFreeze();

    /// @dev Reverts when `freezeAccounts` receives an address that breaks strict sorting.
    error FreezeAccountsAddressesNotSorted(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Sets the token metadata and seeds the initial role assignments for the proxy instance.
     * The `initializer` modifier guarantees that this setup path can run only once.
     *
     * @param tokenName_ ERC20 display name.
     * @param tokenSymbol_ ERC20 ticker symbol.
     * @param mintController_ Address that receives the minter role.
     * @param adminAccount_ Address that receives the default admin role.
     * @param upgradeController_ Address that can authorize implementation upgrades.
     * @param pauseController_ Address that can pause transfers and manage frozen accounts.
     * @param burnOnBehalfOperator_ Address that can burn tokens from third-party accounts.
     */
    function initialize(
        string memory tokenName_,
        string memory tokenSymbol_,
        address mintController_,
        address adminAccount_,
        address upgradeController_,
        address pauseController_,
        address burnOnBehalfOperator_
    )
        external
        virtual
        initializer
    {
        __ERC20_init(tokenName_, tokenSymbol_);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, adminAccount_);
        _grantRole(MINTER_ROLE, mintController_);
        _grantRole(UPGRADER_ROLE, upgradeController_);
        __ERC20Pausable_init();
        __FrozenAccounts_init();
        _grantRole(PAUSER_ROLE, pauseController_);
        _grantRole(BURN_ON_BEHALF_ROLE, burnOnBehalfOperator_);
        __ERC20Permit_init(tokenName_);
    }

    /**
     * @notice Check if an address is frozen.
     *
     * @param account The `address` to check the freeze status of.
     *
     * @return Boolean to indicate if an account is frozen or not.
     */
    function isAccountFrozen(address account) public view virtual returns (bool) {
        return _frozenAccounts[account];
    }

    /**
     * @dev Mints `amount` tokens to `recipient`, materializing supply from the zero address through `_update`.
     *
     * @param recipient Account that receives the freshly minted tokens.
     * @param amount Number of tokens to mint.
     *
     * Emits a {Transfer} event with `from` equal to the zero address.
     */
    function mint(address recipient, uint256 amount) public virtual onlyRole(MINTER_ROLE) {
        _mint(recipient, amount);
    }

    /**
     * @dev Burns `amount` tokens from the caller, reducing the circulating supply through `_update`.
     *
     * @param amount Number of tokens to burn from the caller balance.
     *
     * Emits a {Transfer} event with `to` equal to the zero address.
     */
    function burn(uint256 amount) public virtual onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Burns `amount` tokens from `account`, enabling an authorized third party to reduce supply.
     *
     * @param account Address whose balance is reduced.
     * @param amount Number of tokens to burn.
     *
     * Emits a {Transfer} event with `to` equal to the zero address.
     */
    function burnOnBehalf(address account, uint256 amount) public virtual onlyRole(BURN_ON_BEHALF_ROLE) {
        _burn(account, amount);
    }

    /**
     * @dev Stops token movements globally for the whole contract.
     *
     * Requirements:
     * - The contract must not be paused.
     */
    function pause() public virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Restarts token movements after a global pause.
     *
     * Requirements:
     * - The contract must be paused.
     */
    function unpause() public virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Freezes each account in `targetAccounts`, preventing those addresses from moving tokens.
     *
     * @param targetAccounts Sorted array of accounts to freeze.
     *
     * Requirements:
     * - Each address in `targetAccounts` must be strictly greater than the previous one.
     */
    function freezeAccounts(address[] calldata targetAccounts) public virtual onlyRole(PAUSER_ROLE) {
        address previousAccount = address(0);
        uint256 targetCount = targetAccounts.length;
        require(targetCount != 0, NoAccountsToFreeze());
        for (uint256 i = 0; i < targetCount; ++i) {
            require(targetAccounts[i] > previousAccount, FreezeAccountsAddressesNotSorted(targetAccounts[i]));
            _tryFreezeAccount(targetAccounts[i]);
            previousAccount = targetAccounts[i];
        }
    }

    /**
     * @dev Lifts the freeze flag from a single account.
     *
     * @param targetAccount Address to unfreeze.
     *
     * Requirements:
     * - `targetAccount` must currently be frozen.
     */
    function unfreezeAccount(address targetAccount) public virtual onlyRole(PAUSER_ROLE) {
        _unfreezeAccount(targetAccount);
    }

    /**
     * @dev Keeps the standard approval entrypoint while inheriting pause and freeze restrictions from parents.
     *
     * @param spender Account approved to spend tokens.
     * @param value Number of tokens approved for spending.
     *
     * @return True when the approval succeeds.
     */
    function approve(address spender, uint256 value)
        public
        virtual
        override(ERC20Upgradeable)
        whenAccountNotFrozen(spender)
        whenAccountNotFrozen(_msgSender())
        whenNotPaused
        returns (bool)
    {
        return super.approve(spender, value);
    }

    /**
     * @dev Preserves EIP-2612 permits while applying the same pause and freeze checks used elsewhere.
     *
     * @param owner Token owner that signed the permit.
     * @param spender Account allowed to spend the approved amount.
     * @param value Amount approved for spending.
     * @param deadline Signature expiration timestamp.
     * @param v Recovery id from the permit signature.
     * @param r First 32 bytes of the permit signature.
     * @param s Second 32 bytes of the permit signature.
     *
     * Requirements:
     * - `owner` must not be frozen.
     * - `spender` must not be frozen.
     * - `msg.sender` must not be frozen.
     * - The contract must not be paused.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        virtual
        override(ERC20PermitUpgradeable)
        whenAccountNotFrozen(owner)
        whenAccountNotFrozen(spender)
        whenAccountNotFrozen(_msgSender())
        whenNotPaused
    {
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    /**
     * @dev Restricts UUPS upgrades to accounts holding `UPGRADER_ROLE`.
     */
    function _authorizeUpgrade(address) internal virtual override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Modifier to make a function callable only when the account is not frozen.
     *
     * Requirements:
     * - The account must not already be frozen.
     */
    modifier whenAccountNotFrozen(address account) {
        require(!isAccountFrozen(account), AccountIsFrozen(account));
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the account is frozen.
     *
     * Requirements:
     * - The account must already be frozen.
     */
    modifier whenAccountFrozen(address account) {
        require(isAccountFrozen(account), AccountIsNotFrozen(account));
        _;
    }

    /// @dev Initializes the frozen-accounts module. Call once from the proxy `initialize` path.
    function __FrozenAccounts_init() internal onlyInitializing {}

    /**
     * @dev Freezes `account`. Emits {AccountFrozen}.
     *
     * Requirements:
     * - `account` must not already be frozen.
     */
    function _freezeAccount(address account) internal virtual whenAccountNotFrozen(account) {
        _frozenAccounts[account] = true;
        emit AccountFrozen(account);
    }

    /**
     * @dev Freezes `account` if it is not frozen yet. Emits {AccountFrozen} only on state change.
     *
     * Does not revert when `account` is already frozen (idempotent for batch operations).
     */
    function _tryFreezeAccount(address account) internal virtual {
        if (!_frozenAccounts[account]) {
            _frozenAccounts[account] = true;
            emit AccountFrozen(account);
        }
    }

    /**
     * @dev Unfreezes `account`. Emits {AccountUnfrozen}.
     *
     * Requirements:
     * - `account` must be frozen.
     */
    function _unfreezeAccount(address account) internal virtual whenAccountFrozen(account) {
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    /**
     * @dev Extends the token transfer pipeline with frozen-account checks on both the receiver and caller.
     *
     * Requirements:
     * - `from` must not be frozen, except for `burnOnBehalf` burns performed by another account.
     * - `to` must not be frozen.
     * - `msg.sender` must not be frozen.
     */
    function _update(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
        whenAccountNotFrozen(to)
        whenAccountNotFrozen(_msgSender())
    {
        if (to == address(0) && from != _msgSender()) {
            // Preserve the burn-on-behalf path even if the source account is frozen.
        } else {
            require(!isAccountFrozen(from), AccountIsFrozen(from));
        }
        ERC20PausableUpgradeable._update(from, to, amount);
    }
}
