// Sources flattened with hardhat v2.24.0 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts/utils/Context.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts/access/Ownable.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File @openzeppelin/contracts/security/Pausable.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

pragma solidity ^0.8.0;
/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}


// File @openzeppelin/contracts/interfaces/draft-IERC6093.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (interfaces/draft-IERC6093.sol)
pragma solidity ^0.8.20;

/**
 * @dev Standard ERC-20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC-721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in ERC-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC-1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


// File @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// File @openzeppelin/contracts/token/ERC20/ERC20.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.20;




/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC-20
 * applications.
 */
abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _balances;

    mapping(address account => mapping(address spender => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * Both values are immutable: they can only be set once during construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `value`.
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Skips emitting an {Approval} event indicating an allowance update. This is not
     * required by the ERC. See {xref-ERC20-_approve-address-address-uint256-bool-}[_approve].
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `value`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `value`.
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, lowering the total supply.
     * Relies on the `_update` mechanism.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner`'s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     *
     * ```solidity
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner`'s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}


// File contracts/SKINDEX.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;
contract SKINDEX is ERC20, Ownable {
    address public manager;


    constructor(address initialOwner)
        ERC20("SkinVault ETF", "SKINDEX")
        Ownable(initialOwner)
    {}


    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }


    function mint(address to, uint256 amount) external {
        require(msg.sender == manager || msg.sender == owner(), "Only owner/manager can mint");
        _mint(to, amount);
    }


    function burn(address from, uint256 amount) external {
        require(msg.sender == manager, "Only manager can burn");
        _burn(from, amount);
    }
}


// File @openzeppelin/contracts/security/ReentrancyGuard.sol@v5.3.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}


// File contracts/SkinVault.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;
/// @title  SkinVault – NAV-backed mint/burn of SKINDEX
/// @notice This contract acts as a vault and pool balancer for the SKINDEX ETF token. It tracks ETH, BTC, and CS:GO skin value pools off/on-chain, and enables users to mint and burn SKINDEX for NAV.
/// @dev    BTC and Skins are managed off-chain, while ETH is on-chain. All pool rebalance signals are emitted via events for off-chain bots to execute.
contract SkinVault is Ownable, Pausable, ReentrancyGuard {
    /// @notice The SKINDEX token (ERC20) this vault manages
    SKINDEX public immutable skindex;
    /// @notice Address that can act as the vault manager
    address public vaultManager;
    /// @notice Developer fee recipient
    address public developer;
    /// @notice External ETH hot wallet (e.g., for exchange trades)
    address public ethereumWallet;

    // Vault pool values (in wei-equivalent units for ETH)
    /// @notice Total value of CSGO skins held (off-chain)
    uint256 public skinsVal;
    /// @notice Total value of BTC held (off-chain)
    uint256 public btcVal;

    // Fees (basis points, e.g. 100 = 1%)
    uint256 public devFeeBP  = 100;
    uint256 public mintFeeBP = 0;
    uint256 public burnFeeBP = 500;

    // Pool allocations (basis points)
    uint256 public btcPoolBP  = 1000;
    uint256 public skinPoolBP = 8500;

    // ------------ Events ------------
    /// @notice Emitted when key vault addresses are updated
    event AddressUpdated(string indexed valueType, address newAddress);

    /// @notice Emitted when any numeric value or config is updated
    event ValueUpdated(string indexed valueType, uint256 newValue);

    /// @notice Emitted when ETH is received by the contract directly
    event EthReceivedByContract(uint256 ethValue);
    /// @notice Emitted when ETH is sent from the contract
    event EthSentFromContract(string indexed to, uint256 ethValue);

    /// @notice Emitted when off-chain asset is bought (e.g. BTC, Skins)
    event BoughtOffChainAsset(string indexed valueType, uint256 newValue);
    /// @notice Emitted when off-chain asset is sold (e.g. BTC, Skins)
    event SoldOffChainAsset(string indexed valueType, uint256 newValue);

    /// @notice Emitted on every mint/burn with recommended pool rebalancing
    event PoolAllocation(int256 ethDelta, int256 btcDelta, int256 skinsDelta, uint256 navAfter);

    /// @notice Emitted when a user mints SKINDEX for ETH
    event Minted(address indexed user, uint256 ethIn, uint256 tokensToUser);

    /// @notice Emitted when a user burns SKINDEX for ETH
    event Burned(address indexed user, uint256 tokensBurned, uint256 ethOut);

    /// @notice Emitted if a burn would exceed available ETH
    event RefillContractEth();

    /// @notice Only allow calls from the owner or vaultManager
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == vaultManager, "Not authorized");
        _;
    }

    /// @notice Pause contract (halts mint/burn)
    function pause() external onlyManager { _pause(); }
    /// @notice Unpause contract
    function unpause() external onlyManager { _unpause(); }

    /// @param _initialOwner Deployer/initial owner (also developer address)
    /// @param _skindex Address of SKINDEX token
    /// @param _EthWallet ETH hot wallet for off-chain operations
    constructor(address _initialOwner, address _skindex, address _EthWallet) Ownable(_initialOwner) {
        require(_initialOwner != address(0), "Dev address zero");
        skindex = SKINDEX(_skindex);
        developer = _initialOwner;
        ethereumWallet = _EthWallet;
    }

    /// @notice Set the vault manager address
    function setVaultManager(address manager) external onlyManager {
        vaultManager = manager;
        emit AddressUpdated("Vault Manager", vaultManager);
    }

    /// @notice Set the developer/fee recipient address
    function setDeveloper(address devWallet) external onlyManager {
        require(devWallet != address(0), "Dev wallet zero");
        developer = devWallet;
        emit AddressUpdated("Dev Wallet", devWallet);
    }
    
    /// @notice Set the ETH hot wallet used for external trades
    function setEthWallet(address ethWallet) external onlyManager {
        ethereumWallet = ethWallet;
        emit AddressUpdated("Eth Wallet", ethWallet);
    }
    
    /// @notice Update the off-chain skins pool value (in ETH equivalent)
    function setValSkins(uint256 skinsValue) external onlyManager whenNotPaused {
        skinsVal = skinsValue;
        emit ValueUpdated("SKINS", skinsVal);
    }

    /// @notice Update the off-chain BTC pool value (in ETH equivalent)
    function setValBtc(uint256 btcValue) external onlyManager whenNotPaused {
        btcVal = btcValue;
        emit ValueUpdated("BTC", btcVal);
    }
    
    /// @notice Set the developer fee in basis points (max 5%)
    function setDevFeeBP(uint256 newDevFeeBP) external onlyManager whenNotPaused {
        require(newDevFeeBP <= 500, "Dev fee too high");
        devFeeBP = newDevFeeBP;
        emit ValueUpdated("Dev Fee", devFeeBP);
    }

    /// @notice Set the mint fee in basis points (max 5%)
    function setMintFeeBP(uint256 newMintFeeBP) external onlyManager whenNotPaused {
        require(newMintFeeBP <= 500, "Mint fee too high");
        mintFeeBP = newMintFeeBP;
        emit ValueUpdated("Mint Fee", mintFeeBP);
    }

    /// @notice Set the burn fee in basis points (max 10%)
    function setBurnFeeBP(uint256 newBurnFeeBP) external onlyManager whenNotPaused {
        require(newBurnFeeBP <= 1000, "Burn fee too high");
        burnFeeBP = newBurnFeeBP;
        emit ValueUpdated("Burn Fee", burnFeeBP);
    }

    /// @notice Set the skin pool allocation (basis points, max 100% with BTC)
    function setSkinPoolBP(uint256 newSkinBP) external onlyManager whenNotPaused {
        require(newSkinBP + btcPoolBP <= 10000, "Total allocation exceeds 100%");
        skinPoolBP = newSkinBP;
        emit ValueUpdated("Skin Pool Allocation", skinPoolBP);
    }

    /// @notice Set the BTC pool allocation (basis points, max 100% with SKINS)
    function setBtcPoolBP(uint256 newBtcBP) external onlyManager whenNotPaused {
        require(newBtcBP + skinPoolBP <= 10000, "Total allocation exceeds 100%");
        btcPoolBP = newBtcBP;
        emit ValueUpdated("BTC Pool Allocation", btcPoolBP);
    }

    /// @notice Set both SKINS and BTC pool allocations
    function setPools(uint256 newSkinBP, uint256 newBtcBP) external onlyManager whenNotPaused {
        require(newSkinBP + newBtcBP <= 10000, "Total allocation exceeds 100%");
        skinPoolBP = newSkinBP;
        btcPoolBP = newBtcBP;

        emit ValueUpdated("BTC Pool Allocation", btcPoolBP);
        emit ValueUpdated("Skin Pool Allocation", skinPoolBP);
    }

    /// @notice Get Skin pool target allocation (eth)
    function getSkinTargetValue() public view returns (uint256) {
        return skinPoolBP * NAV();
    }

    /// @notice Get Skin pool allocation (basis points)
    function getSkinPoolBP() public view returns (uint256) {
        return skinPoolBP;
    }

    /// @notice Get BTC pool target allocation (eth)
    function getBtcTargetValue() public view returns (uint256) {
        return btcPoolBP * NAV();
    }

    /// @notice Get BTC pool allocation (basis points)
    function getBtcPoolBP() public view returns (uint256) {
        return btcPoolBP;
    }

    /// @notice Get Eth pool target allocation (eth)
    function getEthTargetValue() public view returns (uint256) {
        return (10000 - skinPoolBP - btcPoolBP) * NAV();
    }

    /// @notice Get ETH pool allocation (basis points)
    function getEthPoolBP() public view returns (uint256) {
        return 10000 - skinPoolBP - btcPoolBP;
    }

    /// @dev Receive function, mints SKINDEX tokens for sent ETH
    receive() external payable {
        mint();
    }

    /// @notice Returns the required deltas for rebalancing pools after a mint or burn
    /// @return (deltaEth, deltaBtc, deltaSkins, futureNAV)
    function manualBalancePools() external onlyManager 
    returns (int256, int256, int256, uint256) {
        (int256 deltaEth, int256 deltaBtc, int256 deltaSkins, uint256 futureNAV) = _calculatePoolDeltas(true, 0);
        emit PoolAllocation(deltaEth, deltaBtc, deltaSkins, futureNAV);
        return (deltaEth, deltaBtc, deltaSkins, futureNAV);
    }

    /// @dev Calculates pool deltas and emits event. Called internally after mint/burn.
    /// @param isMint True if mint, false if burn
    /// @param amountEth The amount of ETH used for mint/burn
    /// @return (deltaEth, deltaBtc, deltaSkins, futureNAV)
    function autoBalancePools(bool isMint, uint256 amountEth) internal
    returns (int256, int256, int256, uint256) {
        (int256 deltaEth, int256 deltaBtc, int256 deltaSkins, uint256 futureNAV) = _calculatePoolDeltas(isMint, amountEth);
        emit PoolAllocation(deltaEth, deltaBtc, deltaSkins, futureNAV);
        return (deltaEth, deltaBtc, deltaSkins, futureNAV);
    }

    /// @dev Computes (x * y) / z safely. Used for fee, allocation, and pool math.
    function _mulDiv(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        require(z != 0, "Div by zero");
        return (x * y) / z;
    }

    /// @notice Calculates pool deltas for balancing after mint/burn
    /// @param isMint True for mint, false for burn
    /// @param amountEth Amount of ETH minted/burned
    function _calculatePoolDeltas(bool isMint, uint256 amountEth ) internal view 
    returns (int256 deltaEth, int256 deltaBtc, int256 deltaSkins, uint256 futureNAV) {
        uint256 currNAV = NAV();
        futureNAV = isMint ? (currNAV + amountEth) : (currNAV > amountEth ? currNAV - amountEth : 0);

        uint256 targetSkins = _mulDiv(futureNAV, skinPoolBP, 10000);
        uint256 targetBtc   = _mulDiv(futureNAV, btcPoolBP , 10000);
        uint256 targetEth   =  futureNAV - targetSkins - targetBtc;

        deltaEth   = int256(targetEth)   - int256(ETH());
        deltaBtc   = int256(targetBtc)   - int256(btcVal);
        deltaSkins = int256(targetSkins) - int256(skinsVal);
    }

    /// @notice Mint SKINDEX tokens by sending ETH to the contract
    function mint() public payable whenNotPaused nonReentrant {
        require(msg.value > 0, "No ETH sent");
        require(NAV() > 0, "No Value could be established");

        uint256 rawMint = _mulDiv(msg.value, SUPPLY(), NAV());

        uint256 dFee = _mulDiv(rawMint, devFeeBP , 10000);
        uint256 mFee = _mulDiv(rawMint, mintFeeBP, 10000);

        uint256 toUser = rawMint - dFee - mFee;

        skindex.mint(msg.sender, toUser);
        if (dFee > 0) skindex.mint(developer, dFee);

        emit Minted(msg.sender, msg.value, toUser);
        autoBalancePools(true, msg.value);
    }

    /// @notice Manually mint SKINDEX tokens to a specific address for off-chain deposits (e.g., skins)
    /// @param recipient The ETH address to receive SKINDEX tokens
    /// @param ethValue The ETH-equivalent value to mint against (e.g., value of deposited skins)
    function mintTo(address recipient, uint256 ethValue) external onlyManager whenNotPaused nonReentrant {
        require(ethValue > 0, "No value");
        require(NAV() > 0, "No Value could be established");

        // Calculate mint amount based on NAV and supply
        uint256 rawMint = _mulDiv(ethValue, SUPPLY(), NAV());

        uint256 dFee = _mulDiv(rawMint, devFeeBP , 10000);
        uint256 mFee = _mulDiv(rawMint, mintFeeBP, 10000);

        uint256 toUser = rawMint - dFee - mFee;

        skindex.mint(recipient, toUser);
        if (dFee > 0) skindex.mint(developer, dFee);

        emit Minted(recipient, ethValue, toUser);
        autoBalancePools(true, ethValue);
    }

    /// @notice Burn SKINDEX tokens to redeem ETH
    /// @param amount Number of tokens to burn
    function burn(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount zero");

        uint256 ethValue = _mulDiv(amount, NAV(), SUPPLY());
        uint256 fee      = _mulDiv(ethValue, burnFeeBP, 10000);
        uint256 payout   = ethValue - fee;

        uint256 contractEth = address(this).balance;

        // Only allow burns up to available contract ETH
        if (contractEth < payout) {
            emit RefillContractEth();
            revert("Not enough ETH in contract for burn payout");
        }

        skindex.burn(msg.sender, amount);
        payable(msg.sender).transfer(payout);

        emit Burned(msg.sender, amount, payout);
        autoBalancePools(false, payout);
    }

    /// @notice Get the SKINDEX token total supply
    function SUPPLY() internal view returns (uint256) {
        return skindex.totalSupply();
    }

    /// @notice Get the current ETH pool (includes contract, vaultManager, and external ETH wallet)
    function ETH() internal view returns (uint256) {
        return address(this).balance + address(ethereumWallet).balance;
    }

    /// @notice Get current NAV (sum of pools)
    function NAV() internal view returns (uint256) {
        return skinsVal + btcVal + ETH();
    }

    /// @notice Returns total ETH (internal/external)
    function getBalETH() external view returns (uint256) {
        return ETH();
    }

    /// @notice Returns NAV
    function getNAV() external view returns (uint256) {
        return NAV();
    }

    /// @notice Returns NAV per token (18 decimals)
    function getNavPerToken() external view returns (uint256) {
        uint256 supply = SUPPLY();
        return supply == 0 ? 0 : _mulDiv(NAV(), 1e18, supply);
    }

    /// @notice Allows the manager to deposit ETH to the contract
    function recieveEth() external payable onlyManager whenNotPaused nonReentrant {
        require(msg.value > 0, "No ETH sent");
        emit EthReceivedByContract(msg.value);
    }

    /// @notice Withdraws ETH from the contract to the hot wallet
    function sendEthToWallet(uint256 ETHValue) external onlyManager nonReentrant {
        require(ETHValue <= address(this).balance, "Insufficient ETH");
        payable(ethereumWallet).transfer(ETHValue);
        emit EthSentFromContract("Wallet", ETHValue);
    }

    /// @notice Add ETH to BTC pool (off-chain operation)
    function EthToBtc(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        btcVal += ETHValue;
        emit BoughtOffChainAsset("BTC", ETHValue);
    }

    /// @notice Remove ETH from BTC pool (off-chain operation)
    function BtcToEth(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        btcVal -= ETHValue;
        emit SoldOffChainAsset("BTC", ETHValue);
    }

    /// @notice Add ETH to Skins pool (off-chain operation)
    function EthToSkins(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        skinsVal += ETHValue;
        emit BoughtOffChainAsset("Skins", ETHValue);
    }

    /// @notice Remove ETH from Skins pool (off-chain operation)
    function SkinsToEth(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        skinsVal -= ETHValue;
        emit SoldOffChainAsset("Skins", ETHValue);
    }
}