// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-v5/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-v5/access/AccessControl.sol";

error ZeroAddressError();
error StartTimeError();
error StartTimeSetError();
error StartTimeNotSetError();
error OnlyWhitelistedTransfersError();
error AmountToClaimTooBigError(uint256 amountToClaim);
error NothingToClaimError();
error AccounMustBePAUSER(address _account);

/**
 * @title SmtVesting
 * @dev Contract module used to lock SMT during Vesting period.
 * @author Swarm
 */
contract SmtVestingV3 {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @dev ERC20 basic token contract being held
    address public acceptedToken;

    /// @dev Distribution start timestamp
    uint256 public vestingStartTime;

    /// @dev Know Your Asset
    string public KYA;

    /// @dev Transferable addresses whitelist
    mapping(address => bool) public whitelisted;

    /// @dev Claimed amount of tokens by address
    mapping(address => uint256) public claimedAmount;

    /// @dev Balances of vSMT3 tokens
    mapping(address => uint256) private _balances;

    /// @dev Total supply of vSMT3 tokens
    uint256 private _totalSupply;

    /// @dev Pausable state
    bool private _paused;

    /// @dev Access control roles
    mapping(bytes32 => mapping(address => bool)) private _roles;

    /**
     * @dev Emitted when `owner` claims.
     * @param owner The address of the owner claiming tokens.
     * @param amount The amount of tokens claimed.
     */
    event Claim(address indexed owner, uint256 amount);

    /**
     * @dev Emitted when `acceptedToken` is set.
     * @param _acceptedToken The address of the accepted token.
     */
    event AcceptedTokenSet(address _acceptedToken);

    /**
     * @dev Emitted when `vestingStartTime` is set.
     * @param vestingStartTime The start time of the vesting period.
     */
    event StartTimeSet(uint256 vestingStartTime);

    /**
     * @dev Emitted when one address is included in the transferable whitelist.
     * @param whitelisted The address added to the whitelist.
     */
    event WhitelistedAddress(address whitelisted);

    /**
     * @dev Emitted when tokens are transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev Emitted when `role` is granted to `account`.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Ensures the address is not zero address.
     * @param _address The address to be checked.
     */
    modifier zeroAddressCheck(address _address) {
        if (_address == address(0)) revert ZeroAddressError();
        _;
    }

    /**
     * @dev Ensures the distribution time is set.
     */
    modifier isDistributionTimeSet() {
        if (vestingStartTime == 0) revert StartTimeNotSetError();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        if (_paused) {
            revert("Pausable: paused");
        }
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        if (!_paused) {
            revert("Pausable: not paused");
        }
        _;
    }

    /**
     * @dev Modifier that checks that an account has a specific role.
     */
    modifier onlyRole(bytes32 role) {
        if (!_roles[role][msg.sender]) {
            revert("AccessControl: account is missing role");
        }
        _;
    }

    /**
     * @dev Constructor for initializing the contract.
     */
    constructor(
        address _admin,
        address _SMT
    ) {
        if (_admin == address(0)) revert ZeroAddressError();
        if (_SMT == address(0)) revert ZeroAddressError();
        acceptedToken = _SMT;
        emit AcceptedTokenSet(_SMT);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @dev Sets the Know Your Asset (KYA) string.
     * @param _KYA The KYA string to be set.
     */
    function setKYA(string calldata _KYA) external onlyRole(DEFAULT_ADMIN_ROLE) {
        KYA = _KYA;
    }

    /**
     * @dev Sets the vesting start time.
     * @param _startTime The start time to be set.
     */
    function setStartTime(uint256 _startTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vestingStartTime > 0) revert StartTimeSetError();
        if (_startTime < block.timestamp) revert StartTimeError();

        vestingStartTime = _startTime;
        emit StartTimeSet(_startTime);
    }

    /**
     * @dev Adds an address to the whitelist.
     * @param _address The address to be added to the whitelist.
     */
    function addWhitelistedAddress(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_address == address(0)) revert ZeroAddressError();
        whitelisted[_address] = true;
        emit WhitelistedAddress(_address);
    }

    /**
     * @dev Deposits tokens to the contract.
     * @param _amount The amount of tokens to be deposited.
     */
    function deposit(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(acceptedToken).transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    /**
     * @dev Claims the specified amount of tokens.
     * @param amount The amount of tokens to claim.
     */
    function claim(uint256 amount) public isDistributionTimeSet {
        uint256 claimableAmount = amountToClaim(msg.sender);
        if (amount == 0) revert NothingToClaimError();
        if (claimableAmount < amount) revert AmountToClaimTooBigError(amount);

        claimedAmount[msg.sender] += amount;
        _burn(msg.sender, amount);

        IERC20(acceptedToken).transfer(msg.sender, amount);

        emit Claim(msg.sender, amount);
    }

    /**
     * @dev Claims the maximum tokens available for the current month.
     */
    function claimMaximumTokensPerMonth() external {
        claim(amountToClaim(msg.sender));
    }

    /**
     * @dev Pauses all token transfers.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Calculates the amount of tokens that can be claimed by the account.
     * @param account The address of the account.
     * @return amount The amount of tokens that can be claimed.
     */
    function amountToClaim(address account) public view returns (uint256 amount) {
        if (vestingStartTime == 0) revert StartTimeNotSetError();

        uint256 initialBalance = _balances[account] + claimedAmount[account];

        if (block.timestamp >= vestingStartTime + (5 * 30 days)) {
            return (initialBalance * 6) / 6 - claimedAmount[account];
        } else if (block.timestamp >= vestingStartTime + (4 * 30 days)) {
            return (initialBalance * 5) / 6 - claimedAmount[account];
        } else if (block.timestamp >= vestingStartTime + (3 * 30 days)) {
            return (initialBalance * 4) / 6 - claimedAmount[account];
        } else if (block.timestamp >= vestingStartTime + (2 * 30 days)) {
            return (initialBalance * 3) / 6 - claimedAmount[account];
        } else if (block.timestamp >= vestingStartTime + (30 days)) {
            return (initialBalance * 2) / 6 - claimedAmount[account];
        } else if (block.timestamp >= vestingStartTime) {
            return (initialBalance / 6) - claimedAmount[account];
        } else {
            return 0;
        }
    }

    /**
     * @dev Returns the current locked amount of accepted tokens in the contract.
     * @return balanceOfAcceptedToken The balance of accepted tokens.
     */
    function getCurrentLockedAmount() external view returns (uint256 balanceOfAcceptedToken) {
        balanceOfAcceptedToken = IERC20(acceptedToken).balanceOf(address(this));
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Returns the total supply of tokens.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _update(address from, address to, uint256 value) internal {
        bool checkTransfer = whitelisted[from] || from == address(0) || to == address(0);
        if (!checkTransfer) revert OnlyWhitelistedTransfersError();

        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert("ERC20: transfer amount exceeds balance");
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) {
            revert("ERC20: mint to the zero address");
        }

        _update(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) {
            revert("ERC20: burn from the zero address");
        }

        _update(account, address(0), amount);
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
}