/*

Wake up, Neo...
The Matrix has you...
Follow the white rabbit.
Knock, knock, Neo.

  _   _              _____                  _____           _                  _ 
 | \ | |            |  __ \                |  __ \         | |                | |
 |  \| | ___  ___   | |__) |__ _ __   ___  | |__) | __ ___ | |_ ___   ___ ___ | |
 | . ` |/ _ \/ _ \  |  ___/ _ \ '_ \ / _ \ |  ___/ '__/ _ \| __/ _ \ / __/ _ \| |
 | |\  |  __/ (_) | | |  |  __/ |_) |  __/ | |   | | | (_) | || (_) | (_| (_) | |
 |_| \_|\___|\___/  |_|   \___| .__/ \___| |_|   |_|  \___/ \__\___/ \___\___/|_|
                              | |                                                
                              |_|                      

*/
// SPDX-License-Identifier: MIT

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

// File @openzeppelin/contracts/access/Ownable.sol@v5.0.2

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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

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
    // function renounceOwnership() public virtual onlyOwner {
    //     _transferOwnership(address(0));
    // }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    // function transferOwnership(address newOwner) public virtual onlyOwner {
    //     if (newOwner == address(0)) {
    //         revert OwnableInvalidOwner(address(0));
    //     }
    //     _transferOwnership(newOwner);
    // }

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

// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

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
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

// File @openzeppelin/contracts/utils/Address.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(
            data
        );
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata
    ) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// File @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(
        address spender,
        uint256 currentAllowance,
        uint256 requestedDecrease
    );

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeCall(token.transferFrom, (from, to, value))
        );
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 requestedDecrease
    ) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(
                    spender,
                    currentAllowance,
                    requestedDecrease
                );
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        bytes memory approvalCall = abi.encodeCall(
            token.approve,
            (spender, value)
        );

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(
                token,
                abi.encodeCall(token.approve, (spender, 0))
            );
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(
        IERC20 token,
        bytes memory data
    ) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return
            success &&
            (returndata.length == 0 || abi.decode(returndata, (bool))) &&
            address(token).code.length > 0;
    }
}

pragma solidity ^0.8.0;

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

pragma solidity ^0.8.0;

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

pragma solidity ^0.8.0;

contract NEOPresale is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    /// @notice Chainlink price oracle to get ETH/USD price (so we stay grounded in reality)
    AggregatorV3Interface public priceFeed;

    /// @notice Decimals used by the price feed (cause precision matters, bruh)
    uint8 public priceFeedDec;

    /// @notice Price per token in USD (because tokens ain't free)
    uint256 public priceInUSD;

    /// @notice Token decimals we're working with (set to 18 like the cool kids)
    uint public immutable saleTokenDec = 18;

    /// @notice Total number of tokens available for degens—I mean, users—to buy
    uint256 public totalTokensforSale;

    /// @notice Tokens (or ETH) allowed to ape into this sale
    mapping(address => bool) public allowedPaymentMethod;

    /// @notice Status of the token sale (true = ON, false = rug—just kidding, OFF)
    bool public saleStatus;

    /// @notice List of all legends who participated
    address[] public participants;

    /// @notice Keep track of whether someone already joined the party
    mapping(address => bool) public participantExists;

    /// @notice How many tokens each chad owns from the sale
    mapping(address => uint256) public balanceOf;

    /// @notice How many tokens each chad owns from the sale per stage
    mapping(address => mapping(uint256 => uint256)) public balanceOfPerStage;

    /// @notice How many unique apes have entered the jungle
    uint256 public totalParticipants;

    /// @notice Counter for how many tokens have been sold so far
    uint256 public totalTokensSold;
    address public feeWallet;
    address public pepeWallet;

    /// @notice Struct to keep track of participant details
    struct ParticipantDetails {
        address buyer;
        uint256 amount;
    }

    /// @notice Event emitted when someone buys the dip (or top, oops)
    event BuyNEOP(
        address indexed buyer,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Constructor sets up Chainlink and fee wallet (and gives us god-mode via Ownable)
    constructor(
        address _aggregatorAddress,
        address _feeWallet,
        address _pepeWallet
    ) Ownable(msg.sender) {
        allowedPaymentMethod[address(0)] = true; // ETH allowed by default

        priceFeed = AggregatorV3Interface(_aggregatorAddress);
        priceFeedDec = priceFeed.decimals();

        feeWallet = _feeWallet;
        pepeWallet = _pepeWallet;
    }

    /// @notice Modifier to allow only when sale is active (aka pump is live)
    modifier saleEnabled() {
        require(saleStatus == true, "ICO is started");
        _;
    }

    /// @notice Modifier to allow only when sale is paused (for cooldown vibes)
    modifier saleStoped() {
        require(saleStatus == false, "ICO is stopped");
        _;
    }

    /// @notice Updates the aggregator address (in case Chainlink goes down)
    function updateAggregator(address _aggregatorAddress) public onlyOwner {
        priceFeed = AggregatorV3Interface(_aggregatorAddress);
        priceFeedDec = priceFeed.decimals();
    }

    /// @notice Rug pulls the sale (legally, of course)
    function stopSale() external onlyOwner saleEnabled {
        saleStatus = false;
    }

    /// @notice Resumes the token sale (back to the moon!)
    function resumeSale() external onlyOwner saleStoped {
        saleStatus = true;
    }

    /// @notice Changes the token price (when the market changes or vibes shift)
    function switchStage(uint256 _priceInUSD) external onlyOwner {
        priceInUSD = _priceInUSD;
    }

    /// @notice Kicks off the presale with new settings (aka fresh tokenomics drop)
    function startMemetrix(
        uint256 _priceInUSD,
        uint256 _totalTokensForSale,
        bool _saleStatus
    ) external onlyOwner {
        priceInUSD = _priceInUSD;
        totalTokensforSale = _totalTokensForSale;
        saleStatus = _saleStatus;
    }

    /// @notice Allows more tokens to be used to buy (multi-coin degen support)
    function addAllowedPayTokens(address[] memory _tokens) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            allowedPaymentMethod[_tokens[i]] = true;
        }
    }

    /// @notice Removes allowed tokens (when they rug or become sus)
    function removeAllowedPayTokens(
        address[] memory _tokens
    ) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            allowedPaymentMethod[_tokens[i]] = false;
        }
    }

    /// @notice Gets current ETH price from Chainlink (so we're not flying blind)
    function getETHPrice() public view returns (uint256) {
        (, int answer, , , ) = priceFeed.latestRoundData();

        return uint256(answer) * (10 ** (18 - priceFeedDec));
    }

    /// @notice Calculates how many tokens you get for the moneyz
    /// @param _token The token you're paying with (or 0x0 for ETH)
    /// @param _amount How much you're throwing at us
    function getTokenAmount(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        uint256 amtOut;
        if (priceInUSD == 0) return 0;

        if (_token != address(0)) {
            require(allowedPaymentMethod[_token], "ERROR");
            uint8 tokenDec = IERC20Metadata(_token).decimals();

            amtOut =
                (_amount * (10 ** ((saleTokenDec * 2) - tokenDec))) /
                priceInUSD;
        } else {
            uint256 ethPrice = getETHPrice();

            amtOut =
                ((_amount * (10 ** (18 - saleTokenDec))) * ethPrice) /
                priceInUSD;
        }
        return amtOut;
    }

    /// @notice Handles the money side of the buy
    function transferFunds(address _token, uint256 _amount) internal {
        uint256 feeAmt = (_amount * 5) / 100;

        if (_token == address(0)) {
            // ETH path
            payable(feeWallet).transfer(feeAmt);
            payable(pepeWallet).transfer(_amount - feeAmt);
        } else {
            // ERC20 path
            IERC20(_token).safeTransferFrom(msg.sender, feeWallet, feeAmt);
            IERC20(_token).safeTransferFrom(
                msg.sender,
                pepeWallet,
                _amount - feeAmt
            );
        }
    }

    /// @notice Main buy function—send in money, get tokens, become legend
    function buyNeoPepe(
        address _token,
        uint256 _amount,
        uint256 _stage
    ) external payable saleEnabled {
        uint256 amount = _token != address(0) ? _amount : msg.value;
        uint256 saleTokenAmt = getTokenAmount(_token, amount);

        require(saleTokenAmt != 0, "ERROR");
        require((totalTokensSold + saleTokenAmt) < totalTokensforSale, "ERROR");

        transferFunds(_token, _token == address(0) ? msg.value : _amount);

        totalTokensSold += saleTokenAmt;

        if (!participantExists[msg.sender]) {
            participants.push(msg.sender);
            participantExists[msg.sender] = true;
            totalParticipants += 1;
        }

        balanceOf[msg.sender] += saleTokenAmt;
        balanceOfPerStage[msg.sender][_stage] += saleTokenAmt;

        emit BuyNEOP(msg.sender, _token, amount, saleTokenAmt);
    }

    /// @notice Gets all the participants details (for analytics)
    function participantsDetailsList(
        uint _from,
        uint _to
    ) external view returns (ParticipantDetails[] memory) {
        require(_from < _to, "_from should be less than _to");

        uint to = _to > totalParticipants ? totalParticipants : _to;
        uint from = _from > totalParticipants ? totalParticipants : _from;

        ParticipantDetails[]
            memory participantsDetails = new ParticipantDetails[](to - from);

        for (uint i = from; i < to; i += 1) {
            participantsDetails[i] = ParticipantDetails(
                participants[i],
                balanceOf[participants[i]]
            );
        }

        return participantsDetails;
    }

    /// @notice In case something gets stuck, devs can save the day
    function emergencyWithdraw(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        if (_token == address(0)) {
            // Save stuck ETH
            payable(owner()).transfer(_amount);
        } else {
            // Save stuck ERC20
            IERC20(_token).safeTransfer(owner(), _amount);
        }
    }
}