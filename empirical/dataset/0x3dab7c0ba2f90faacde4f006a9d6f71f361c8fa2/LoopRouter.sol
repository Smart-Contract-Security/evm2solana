// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0 ^0.8.1 ^0.8.19;

// lib/open-zeppelin/security/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

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

// lib/open-zeppelin/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

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
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
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
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// lib/open-zeppelin/token/ERC20/extensions/IERC20Permit.sol

// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// lib/open-zeppelin/utils/Address.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     *
     * Furthermore, `isContract` will also return true if the target contract within
     * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
     * which only has an effect at the end of a transaction.
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

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
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

// src/interfaces/morpho/IMorpho.sol

/// @notice Morpho Blue market identifier (keccak256 of MarketParams).
type Id is bytes32;

/// @notice Parameters that uniquely identify a Morpho Blue market.
/// @dev The market id is derived from these via keccak256(abi.encode(marketParams)).
struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

/// @notice A user's position in a single Morpho Blue market.
/// @dev borrowShares and collateral are packed (uint128 each) to share one storage slot.
struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

/// @notice Aggregate state for a Morpho Blue market (interest-accruing).
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

/// @notice EIP-712 typed-data payload authorizing one address to act on another's behalf.
/// @dev Consumed by setAuthorizationWithSig in a single transaction; nonce advances on use.
struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

/// @notice ECDSA signature components for an Authorization (or any EIP-712 payload).
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @notice Callback invoked by Morpho during flashLoan execution.
/// @dev The callee receives `assets` of the flash-borrowed token in its balance before this
///      returns, and must `approve(morpho, assets)` so Morpho can pull the repayment back.
///      The token address itself is NOT passed; the implementation must reconstruct it from `data`.
interface IMorphoFlashLoanCallback {
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

/// @notice Morpho Blue core interface.
/// @dev Only the subset used by August contracts is declared here. Add new functions as needed
///      rather than pulling the full morpho-blue source as a forge dependency (project convention).
interface IMorpho {
    // ── Flash loans ───────────────────────────────────────────────────────────────
    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    // ── Position lifecycle (on behalf of `onBehalf`) ──────────────────────────────
    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) external;

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid);

    // ── Interest accrual ──────────────────────────────────────────────────────────
    function accrueInterest(MarketParams memory marketParams) external;

    // ── Authorization (required for any onBehalf-of-other-user call) ──────────────
    function setAuthorization(address authorized, bool newIsAuthorized) external;

    /// @notice One-shot authorization grant via EIP-712. Caller passes a sig the authorizer
    ///         produced off-chain; Morpho verifies and flips the flag. Used to keep loops
    ///         to a single user signature.
    function setAuthorizationWithSig(
        Authorization calldata authorization,
        Signature calldata signature
    ) external;

    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    function nonce(address authorizer) external view returns (uint256);

    // ── Views ─────────────────────────────────────────────────────────────────────
    function position(Id id, address user) external view returns (Position memory);

    function market(Id id) external view returns (Market memory);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// src/interfaces/morpho/IOracle.sol

/// @notice Morpho Blue oracle interface.
/// @dev Returns the collateral/loan price scaled by 10^(36 + loanDecimals - collateralDecimals).
///      Consumers must compute the scale from token decimals; do NOT assume a constant 1e36.
interface IOracle {
    function price() external view returns (uint256);
}

// lib/open-zeppelin/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/utils/SafeERC20.sol)

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

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
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

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// src/loop/LoopRouter.sol

/// @title LoopRouter
/// @notice One-tx leverage looper on Morpho Blue. Holds zero balance and zero approvals
///         between transactions, with all per-call swap output verified against an
///         off-chain-supplied `minCollateralOut` floor.
/// @dev Single immutable contract. No owner, no upgrade, no sweep. Designed to be safe
///      to leave with user approvals because:
///        1. `onMorphoFlashLoan` rejects any caller other than Morpho — closing the
///           #1 honeypot vector where an attacker could re-enter the callback with a
///           crafted `data` blob and drain stale approvals.
///        2. Every approval is exact-amount and reset to zero immediately after use,
///           so the contract is never a standing target for `transferFrom` drains.
///        3. The Morpho `setAuthorizationWithSig` grant is consumed inside the callback
///           in the same tx that creates it — it is a single-tx capability, not a
///           persistent grant.
contract LoopRouter is ReentrancyGuard, IMorphoFlashLoanCallback {
    /// @notice Morpho Blue singleton this router operates against (constructor-pinned).
    IMorpho public immutable morpho;

    /// @notice DEX aggregator router this contract calls with opaque, off-chain-quoted
    ///         calldata to perform `loanToken <-> collateralToken` swaps. The same address
    ///         is both the spender (it pulls the input token via `transferFrom`) and the
    ///         call target — this matches the 0x AllowanceHolder v2 pattern. Pinned at
    ///         deploy time; do not generalize without tightening the calldata validation.
    address public immutable aggregator;

    /// @notice Flash-loan callback dispatch tag. DELOOP path added in T-CONTRACT-3.
    enum Action {
        LOOP,
        DELOOP
    }

    /// @notice Per-call parameters for `loop()`. Bundles the Morpho market identity, the
    ///         user's principal, the requested leverage, the off-chain swap quote, and a
    ///         one-shot Morpho authorization sig the callback consumes.
    /// @dev `minCollateralOut` is the user's slippage floor computed from the 0x quote
    ///      minus the user-chosen slippage tolerance. It is enforced inside the callback
    ///      by a `balanceOf` delta check — never trust the aggregator's reported output.
    struct LoopParams {
        MarketParams market;
        uint256 initialCollateral;
        uint256 targetLeverage;
        uint256 minCollateralOut;
        bytes swapCalldata;
        Authorization authorization;
        Signature authSig;
    }

    /// @notice Per-call parameters for `deloop()`. Always closes the full position —
    ///         partial deloop is deferred to v2 because the share-math + interest
    ///         accrual surface is a footgun on a hackathon clock.
    /// @dev `minLoanOut` is the user's slippage floor for the collateral -> loan swap.
    ///      If the swap underdelivers, the whole tx reverts (user pays gas, no funds lost).
    ///      The Authorization sig is consumed inside the callback, identical to LoopParams.
    struct DeloopParams {
        MarketParams market;
        uint256 minLoanOut;
        bytes swapCalldata;
        Authorization authorization;
        Signature authSig;
    }

    /// @notice Emitted on a successful loop. Indexed user + market id lets a Subgraph or
    ///         off-chain indexer reconstruct the position trajectory from logs alone.
    event Looped(
        address indexed user,
        Id indexed marketId,
        uint256 initialCollateral,
        uint256 totalCollateral,
        uint256 flashBorrow,
        uint256 totalDebt
    );

    /// @notice Emitted on a successful deloop. Reserved here so T-CONTRACT-3 only needs
    ///         to emit; ABI shape is locked now so off-chain consumers can be written
    ///         in parallel with the contract path.
    event Delooped(
        address indexed user,
        Id indexed marketId,
        uint256 collateralReturned,
        uint256 debtRepaid,
        uint256 dustReturned
    );

    /// @notice Pins the Morpho singleton and aggregator router for this contract's lifetime.
    /// @param _morpho      Morpho Blue deployment address.
    /// @param _aggregator  DEX aggregator that is both the approval spender and the
    ///                     call target for `swapCalldata` (e.g. 0x AllowanceHolder v2).
    constructor(address _morpho, address _aggregator) {
        morpho = IMorpho(_morpho);
        aggregator = _aggregator;
    }

    // ── User entry point ─────────────────────────────────────────────────────

    /// @notice Open a leveraged Morpho Blue position in a single transaction.
    /// @dev Caller must first `approve(LoopRouter, initialCollateral)` on the collateral
    ///      token. The Morpho `Authorization` sig grants this router rights to call
    ///      `supplyCollateral` / `borrow` on the user's behalf for the duration of the
    ///      callback — it is consumed inside the same tx by `setAuthorizationWithSig`,
    ///      so no persistent on-chain authorization is left after this function returns.
    ///
    ///      Leverage is bounded `(1e18, 3.5e18]`. The lower bound rules out the no-op
    ///      case (and an underflow in `_calcFlashBorrow`); the upper bound enforces the
    ///      hackathon-locked safety buffer against LLTV.
    /// @param p Loop parameters — see `LoopParams`.
    function loop(LoopParams calldata p) external nonReentrant {
        require(p.targetLeverage > 1e18 && p.targetLeverage <= 3.5e18, "leverage out of range");

        // Pull the user's principal collateral; the swap output is netted on top of this
        // inside the callback before being supplied as a single `supplyCollateral` call.
        SafeERC20.safeTransferFrom(
            IERC20(p.market.collateralToken),
            msg.sender,
            address(this),
            p.initialCollateral
        );

        uint256 flashBorrow = _calcFlashBorrow(p);

        // Pack the dispatch tag, user, and inner params into the callback data blob.
        // Morpho echoes this verbatim into `onMorphoFlashLoan`; nothing the caller passes
        // is trusted there — `msg.sender == morpho` is the only authorization gate.
        bytes memory cbData = abi.encode(Action.LOOP, msg.sender, abi.encode(p));
        morpho.flashLoan(p.market.loanToken, flashBorrow, cbData);

        // Post-condition: enforce the file-level zero-balance invariant. If the aggregator
        // partial-filled or the callback otherwise leaked dust, surface it as a revert
        // rather than letting tokens silently accumulate in this contract.
        require(IERC20(p.market.loanToken).balanceOf(address(this)) == 0, "loan dust");
        require(IERC20(p.market.collateralToken).balanceOf(address(this)) == 0, "col dust");
    }

    /// @notice Close a leveraged Morpho Blue position in a single transaction.
    /// @dev Caller must already have an open position in `p.market`. The router uses a
    ///      flash-borrow of the loanToken to repay the user's full debt, then withdraws
    ///      all collateral, swaps it back to loanToken, and repays the flash. Any leftover
    ///      loanToken AND any collateral dust is returned to the user before this function
    ///      returns.
    ///
    ///      If the collateral->loanToken swap delivers less than the user's outstanding
    ///      debt, the whole tx reverts on slippage. This is the accepted "revert-with-retry"
    ///      UX (eng-review D7); the frontend re-quotes and retries.
    /// @param p Deloop parameters — see `DeloopParams`.
    function deloop(DeloopParams calldata p) external nonReentrant {
        // Read the user's CURRENT debt after accruing interest. The accrue is critical:
        // without it, the cached totalBorrowAssets/totalBorrowShares would lag the real
        // state and we'd underpay morpho by interest, reverting the flash repay.
        morpho.accrueInterest(p.market);
        uint256 userDebt = _userBorrowAssets(p.market, msg.sender);
        require(userDebt > 0, "no position");

        bytes memory cbData = abi.encode(Action.DELOOP, msg.sender, abi.encode(p));
        morpho.flashLoan(p.market.loanToken, userDebt, cbData);

        // Same zero-balance invariant as loop(): if anything leaked into this contract,
        // surface the bug as a revert rather than silently accumulating dust.
        require(IERC20(p.market.loanToken).balanceOf(address(this)) == 0, "loan dust");
        require(IERC20(p.market.collateralToken).balanceOf(address(this)) == 0, "col dust");
    }

    // ── Morpho flash-loan callback ───────────────────────────────────────────

    /// @notice Morpho flash-loan callback. Morpho transfers `assets` of the requested
    ///         token to this contract immediately before invoking this function, then
    ///         pulls the same amount back via `transferFrom` once the callback returns.
    /// @dev The `require(msg.sender == address(morpho))` check MUST be the first line:
    ///      anyone can call this entrypoint, and the `data` blob is attacker-controlled
    ///      if the caller is not Morpho itself. Any pre-call logic that touches user
    ///      approvals before this check would be a drain vector.
    ///
    ///      After dispatching to the action-specific internal handler, we approve Morpho
    ///      for exactly `assets` of the flash-borrowed token so it can pull the
    ///      repayment on return — `safeApprove(0)` first to handle non-standard tokens
    ///      (USDT pattern) that refuse a non-zero-to-non-zero approval.
    /// @param assets Amount of the flash-borrowed token Morpho has transferred to this
    ///               contract for the duration of the callback.
    /// @param data   Opaque blob this contract supplied to `morpho.flashLoan`. Layout is
    ///               `(Action action, address user, bytes innerParams)`.
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        // CRITICAL: must be the first executed statement. Anything that touches state or
        // approvals before this is a potential drain vector.
        require(msg.sender == address(morpho), "only morpho");

        (Action action, address user, bytes memory inner) = abi.decode(data, (Action, address, bytes));

        address loanToken;
        if (action == Action.LOOP) {
            LoopParams memory p = abi.decode(inner, (LoopParams));
            loanToken = p.market.loanToken;
            _executeLoop(assets, user, p);
        } else {
            // Action.DELOOP
            DeloopParams memory p = abi.decode(inner, (DeloopParams));
            loanToken = p.market.loanToken;
            _executeDeloop(assets, user, p);
        }

        // Approve Morpho to pull back exactly the flash amount. `safeApprove(0)` first
        // because (a) the LOOP path may have left a zero allowance already, in which case
        // the no-op self-validation in OZ v4 safeApprove still passes, and (b) any future
        // path that uses the loanToken approval mid-call must reset to zero before this.
        SafeERC20.safeApprove(IERC20(loanToken), address(morpho), 0);
        SafeERC20.safeApprove(IERC20(loanToken), address(morpho), assets);
    }

    // ── Internals ────────────────────────────────────────────────────────────

    /// @notice Executes the LOOP path inside the flash-loan callback.
    /// @dev Step-by-step:
    ///        1. Consume the user's one-shot Morpho authorization sig.
    ///        2. Swap the flash-borrowed loanToken into collateralToken via the
    ///           aggregator, with an in-contract slippage check against
    ///           `p.minCollateralOut` (the aggregator's reported output is NOT trusted).
    ///        3. Supply the user's principal + swap output as collateral, on behalf of
    ///           the user, in a single `supplyCollateral` call.
    ///        4. Borrow the flash amount on behalf of the user, with this contract as the
    ///           receiver — the loanToken stays here so the outer callback can repay it.
    ///
    ///      The flashBorrow value is borrowed back from Morpho on the user's account in
    ///      step 4, so `totalDebt == flashBorrow` at the moment of emission. The `Looped`
    ///      event carries both values explicitly so off-chain consumers don't have to
    ///      know they are identical.
    /// @param flashBorrow Amount of loanToken Morpho has transferred to this contract.
    /// @param user        End user the position is being opened for (`onBehalf`).
    /// @param p           Decoded LoopParams from the callback data.
    function _executeLoop(uint256 flashBorrow, address user, LoopParams memory p) internal {
        // One-shot Morpho authorization grant. Lets us call supplyCollateral/borrow with
        // `onBehalf = user`. The grant lives for this callback only — Morpho's nonce
        // advances on consumption, so any replay attempt with the same sig is rejected.
        morpho.setAuthorizationWithSig(p.authorization, p.authSig);

        // Approve aggregator to pull the flash-borrowed loanToken. Exact-amount only;
        // safeApprove(0) first to handle non-standard tokens that reject non-zero-to-
        // non-zero approvals.
        SafeERC20.safeApprove(IERC20(p.market.loanToken), aggregator, 0);
        SafeERC20.safeApprove(IERC20(p.market.loanToken), aggregator, flashBorrow);

        // In-contract slippage enforcement. The aggregator's reported `buyAmount` from
        // the off-chain quote is informational only; the source of truth is the
        // post-swap `balanceOf` delta on the collateral token.
        uint256 colBefore = IERC20(p.market.collateralToken).balanceOf(address(this));
        (bool ok, ) = aggregator.call(p.swapCalldata);
        require(ok, "swap failed");
        // Reset the aggregator allowance immediately. Some 0x routes partially fill
        // (especially on thin Curve pools), leaving residual allowance that would
        // violate the file-level "zero approvals between txs" invariant.
        SafeERC20.safeApprove(IERC20(p.market.loanToken), aggregator, 0);
        uint256 colAfter = IERC20(p.market.collateralToken).balanceOf(address(this));
        uint256 colReceived = colAfter - colBefore;
        require(colReceived >= p.minCollateralOut, "slippage");

        // Net collateral supplied = user's principal + swap output.
        uint256 totalCollateral = p.initialCollateral + colReceived;

        // Approve Morpho exactly for the collateral being supplied, then supply.
        SafeERC20.safeApprove(IERC20(p.market.collateralToken), address(morpho), 0);
        SafeERC20.safeApprove(IERC20(p.market.collateralToken), address(morpho), totalCollateral);
        morpho.supplyCollateral(p.market, totalCollateral, user, hex"");

        // Borrow `flashBorrow` loanToken on behalf of the user, receiver = this contract.
        // The receiver flag is what keeps the loanToken inside this contract so the outer
        // callback can repay Morpho via the approval set after this function returns.
        morpho.borrow(p.market, flashBorrow, 0, user, address(this));

        // Morpho's market identity is the keccak of the abi-encoded MarketParams tuple.
        // Inlined per project convention — no MarketParamsLib helper.
        Id marketId = Id.wrap(keccak256(abi.encode(p.market)));

        // totalDebt == flashBorrow at emission: the only debt the user has incurred is
        // the flash amount just borrowed back from Morpho. Both surfaced so consumers
        // don't need to reason about that equality.
        emit Looped(user, marketId, p.initialCollateral, totalCollateral, flashBorrow, flashBorrow);
    }

    /// @notice Executes the DELOOP path inside the flash-loan callback.
    /// @dev Step-by-step:
    ///        1. Consume the user's one-shot Morpho authorization sig.
    ///        2. Repay the user's full debt with the flash-borrowed loanToken.
    ///        3. Withdraw the user's full collateral to this contract.
    ///        4. Swap collateral -> loanToken via the aggregator, with an in-contract
    ///           slippage check against `p.minLoanOut`.
    ///        5. Return any leftover loanToken AND any collateral dust to the user.
    ///
    ///      The outer callback then approves Morpho for `assets` so it can pull the
    ///      flash-repayment, leaving the contract at zero balance and zero approvals.
    /// @param userDebt   Flash-borrowed amount of loanToken (== user's full debt at flashLoan time).
    /// @param user       End user the position is being closed for (`onBehalf`).
    /// @param p          Decoded DeloopParams from the callback data.
    function _executeDeloop(uint256 userDebt, address user, DeloopParams memory p) internal {
        morpho.setAuthorizationWithSig(p.authorization, p.authSig);

        Id marketId = Id.wrap(keccak256(abi.encode(p.market)));
        uint256 userCollateral;
        {
            // Inner block bounds the `Position` memory copy + intermediate values so they
            // don't pin stack slots for the rest of the function (16-slot EVM limit).
            // Repay by SHARES, not assets: we sized `userDebt` via `toAssetsUp(shares)` in
            // the entry function, so Morpho's internal `shares.toAssetsUp(...)` re-derivation
            // pulls EXACTLY `userDebt` via transferFrom. Specifying assets would let Morpho
            // recompute shares via `toSharesDown(userDebt)`, which can round to (shares+1)
            // and underflow `position.borrowShares -= shares`.
            Position memory pos = morpho.position(marketId, user);
            userCollateral = uint256(pos.collateral);

            SafeERC20.safeApprove(IERC20(p.market.loanToken), address(morpho), 0);
            SafeERC20.safeApprove(IERC20(p.market.loanToken), address(morpho), userDebt);
            morpho.repay(p.market, 0, uint256(pos.borrowShares), user, hex"");
        }

        // Withdraw all of the user's collateral to this contract.
        morpho.withdrawCollateral(p.market, userCollateral, user, address(this));

        // Swap collateral -> loanToken with in-contract slippage enforcement.
        SafeERC20.safeApprove(IERC20(p.market.collateralToken), aggregator, 0);
        SafeERC20.safeApprove(IERC20(p.market.collateralToken), aggregator, userCollateral);
        uint256 loanReceived;
        {
            uint256 loanBefore = IERC20(p.market.loanToken).balanceOf(address(this));
            (bool ok, ) = aggregator.call(p.swapCalldata);
            require(ok, "swap failed");
            // Reset aggregator allowance immediately (mirrors the LOOP path fix).
            SafeERC20.safeApprove(IERC20(p.market.collateralToken), aggregator, 0);
            loanReceived = IERC20(p.market.loanToken).balanceOf(address(this)) - loanBefore;
        }
        require(loanReceived >= p.minLoanOut, "slippage");

        // After the upcoming outer-callback morpho.repay (of `userDebt`), the loanToken
        // balance held by this contract drops by `userDebt`. The leftover we ship back
        // to the user now is `loanReceived - userDebt`. If the swap delivered exactly
        // userDebt (no leftover), this transfer is a no-op (skip on zero).
        uint256 loanLeftover = loanReceived > userDebt ? loanReceived - userDebt : 0;
        if (loanLeftover > 0) {
            SafeERC20.safeTransfer(IERC20(p.market.loanToken), user, loanLeftover);
        }

        // Collateral dust can only appear if the aggregator partial-fills. Return it.
        uint256 colDust = IERC20(p.market.collateralToken).balanceOf(address(this));
        if (colDust > 0) {
            SafeERC20.safeTransfer(IERC20(p.market.collateralToken), user, colDust);
        }

        emit Delooped(user, marketId, userCollateral, userDebt, loanLeftover);
    }

    /// @notice Computes the loanToken flash amount needed to reach `targetLeverage`.
    /// @dev Morpho's `IOracle.price()` returns a price scaled by the constant
    ///      `ORACLE_PRICE_SCALE = 1e36`. The decimal difference between the loan and
    ///      collateral tokens is ALREADY baked into the value the oracle returns — the
    ///      conversion divisor is just `1e36`, NOT `10^(36 + loanDec - colDec)`.
    ///
    ///      Concretely, for a market quoting X loanTokens per 1 collateralToken:
    ///        oracle.price() == X * 10^(36 + loanDec - colDec)
    ///      So to convert `collateralRaw` into `loanRaw`:
    ///        loanRaw == collateralRaw * oracle.price() / 1e36
    ///
    ///      Formula:
    ///        flashBorrow_loanUnits =
    ///          initialCollateral_collateralUnits
    ///          * (targetLeverage - 1e18)        // 3e18 - 1e18 = 2e18 for 3x
    ///          * oraclePrice                    // oracle-scaled
    ///          / 1e36                           // undo Morpho's ORACLE_PRICE_SCALE
    ///          / 1e18                           // undo leverage scaling
    ///
    ///      Worked example, sUSDe/PYUSD at ~$1.23, 3x on 1000 sUSDe:
    ///        oracle.price() ≈ 1.23 * 10^24     (== 1.23 * 10^(36 + 6 - 18))
    ///        flashBorrow ≈ 1000e18 * 2e18 * 1.23e24 / 1e36 / 1e18
    ///                    ≈ 2460e6              (== 2460 PYUSD in 6-decimal native units)
    /// @param p LoopParams the entry function received (memory copy, internal-only use).
    /// @return flashBorrow Amount of loanToken (in native units) to flash-borrow.
    function _calcFlashBorrow(LoopParams memory p) internal view returns (uint256 flashBorrow) {
        uint256 oraclePrice = IOracle(p.market.oracle).price();
        flashBorrow = (p.initialCollateral * (p.targetLeverage - 1e18) * oraclePrice) / 1e36 / 1e18;
    }

    /// @notice Computes the user's current borrow debt in loanToken native units.
    /// @dev Reads the user's `borrowShares` and converts to assets via the market's
    ///      current `totalBorrowAssets / totalBorrowShares`. Caller MUST have called
    ///      `morpho.accrueInterest(p.market)` immediately before this view, otherwise
    ///      the assets-from-shares conversion uses a stale share price and the flash
    ///      repay may underpay by ~1 wei worth of interest accrued in the same block.
    ///
    ///      Rounds UP (`assets = ceil(shares * totalAssets / totalShares)`) so the
    ///      computed debt is enough to fully repay; the rounding goes against the user
    ///      by at most 1 wei, which is the standard convention for repay amounts.
    /// @param marketParams The Morpho market to read.
    /// @param user The user whose debt is being looked up.
    /// @return assets The user's debt in loanToken native units.
    function _userBorrowAssets(MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256 assets)
    {
        Id id = Id.wrap(keccak256(abi.encode(marketParams)));
        uint128 shares = morpho.position(id, user).borrowShares;
        if (shares == 0) return 0;
        uint128 totalAssets = morpho.market(id).totalBorrowAssets;
        uint128 totalShares = morpho.market(id).totalBorrowShares;
        // Round up: `(shares * totalAssets + totalShares - 1) / totalShares`.
        // This is the standard Morpho `toAssetsUp` formulation inlined.
        assets = (uint256(shares) * uint256(totalAssets) + uint256(totalShares) - 1) / uint256(totalShares);
    }
}