// SPDX-License-Identifier: MIT

/// @notice Safe ETH and ERC20 transfer library that gracefully handles missing return values.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @author Permit2 operations from (https://github.com/Uniswap/permit2/blob/main/src/libraries/Permit2Lib.sol)
///
/// @dev Note:
/// - For ETH transfers, please use `forceSafeTransferETH` for DoS protection.
library SafeTransferLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ETH transfer has failed.
    uint64 constant ETHTransferFailed = 0xb12d13eb;

    /// @dev The ERC20 `transferFrom` has failed.
    uint64 constant TransferFromFailed = 0x7939f424;

    /// @dev The ERC20 `transfer` has failed.
    uint64 constant TransferFailed = 0x90b8ec18;

    /// @dev The ERC20 `approve` has failed.
    uint64 constant ApproveFailed = 0x3e3f8f73;

    /// @dev The ERC20 `totalSupply` query has failed.
    uint64 constant TotalSupplyQueryFailed = 0x54cd9435;

    /// @dev The Permit2 operation has failed.
    uint64 constant Permit2Failed = 0x6b836e6b;

    /// @dev The Permit2 amount must be less than `2**160 - 1`.
    uint64 constant Permit2AmountOverflow = 0x8757f0fd;

    /// @dev The Permit2 approve operation has failed.
    uint64 constant Permit2ApproveFailed = 0x324f14ae;

    /// @dev The Permit2 lockdown operation has failed.
    uint64 constant Permit2LockdownFailed = 0x96b3de23;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Suggested gas stipend for contract receiving ETH that disallows any storage writes.
    uint64 internal constant GAS_STIPEND_NO_STORAGE_WRITES = 2300;

    /// @dev Suggested gas stipend for contract receiving ETH to perform a few
    /// storage reads and writes, but low enough to prevent griefing.
    uint64 internal constant GAS_STIPEND_NO_GRIEF = 100000;

    /// @dev The unique EIP-712 domain separator for the DAI token contract.
    bytes32 internal constant DAI_DOMAIN_SEPARATOR =
        0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7;

    /// @dev The address for the WETH9 contract on Ethereum mainnet.
    /// Not available on Solana; placeholder address.
    address internal constant WETH9 = address(0);

    /// @dev The canonical Permit2 address.
    /// Not available on Solana; placeholder address.
    address internal constant PERMIT2 = address(0);

    /// @dev The canonical address of the `SELFDESTRUCT` ETH mover.
    /// Not available on Solana; placeholder address.
    address internal constant ETH_MOVER = address(0);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ETH OPERATIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // If the ETH transfer MUST succeed with a reasonable gas budget, use the force variants.
    //
    // The regular variants:
    // - Forwards all remaining gas to the target.
    // - Reverts if the target reverts.
    // - Reverts if the current contract has insufficient balance.
    //
    // The force variants:
    // - Forwards with an optional gas stipend
    //   (defaults to `GAS_STIPEND_NO_GRIEF`, which is sufficient for most cases).
    // - If the target reverts, or if the gas stipend is exhausted,
    //   creates a temporary contract to force send the ETH via `SELFDESTRUCT`.
    //   Future compatible with `SENDALL`: https://eips.ethereum.org/EIPS/eip-4758.
    // - Reverts if the current contract has insufficient balance.
    //
    // The try variants:
    // - Forwards with a mandatory gas stipend.
    // - Instead of reverting, returns whether the transfer succeeded.

    /// @dev Sends `amount` (in wei) ETH to `to`.
    function safeTransferETH(address to, uint64 amount) internal {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Sends all the ETH in the current contract to `to`.
    function safeTransferAllETH(address to) internal {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Force sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function forceSafeTransferETH(address to, uint64 amount, uint64 gasStipend) internal {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Force sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function forceSafeTransferAllETH(address to, uint64 gasStipend) internal {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Force sends `amount` (in wei) ETH to `to`, with `GAS_STIPEND_NO_GRIEF`.
    function forceSafeTransferETH(address to, uint64 amount) internal {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Force sends all the ETH in the current contract to `to`, with `GAS_STIPEND_NO_GRIEF`.
    function forceSafeTransferAllETH(address to) internal {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function trySafeTransferETH(address to, uint64 amount, uint64 gasStipend)
        internal
        returns (bool success)
    {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function trySafeTransferAllETH(address to, uint64 gasStipend)
        internal
        returns (bool success)
    {
        revert("ETH transfers not supported on Solana");
    }

    /// @dev Force transfers ETH to `to`, without triggering the fallback (if any).
    /// This method attempts to use a separate contract to send via `SELFDESTRUCT`,
    /// and upon failure, deploys a minimal vault to accrue the ETH.
    function safeMoveETH(address to, uint64 amount) internal returns (address vault) {
        revert("ETH transfers not supported on Solana");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ERC20 OPERATIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    function safeTransferFrom(address token, address from, address to, uint64 amount) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function trySafeTransferFrom(address token, address from, address to, uint64 amount)
        internal
        returns (bool success)
    {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sends all of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have their entire balance approved for the current contract to manage.
    function safeTransferAllFrom(address token, address from, address to)
        internal
        returns (uint64 amount)
    {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransfer(address token, address to, uint64 amount) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sends all of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransferAll(address token, address to) internal returns (uint64 amount) {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// Reverts upon failure.
    function safeApprove(address token, address to, uint64 amount) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// If the initial attempt to approve fails, attempts to reset the approved amount to zero,
    /// then retries the approval again (some tokens, e.g. USDT, requires this).
    /// Reverts upon failure.
    function safeApproveWithRetry(address token, address to, uint64 amount) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Returns the amount of ERC20 `token` owned by `account`.
    /// Returns zero if the `token` does not exist.
    function balanceOf(address token, address account) internal view returns (uint64 amount) {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Performs a `token.balanceOf(account)` check.
    /// `implemented` denotes whether the `token` does not implement `balanceOf`.
    /// `amount` is zero if the `token` does not implement `balanceOf`.
    function checkBalanceOf(address token, address account)
        internal
        view
        returns (bool implemented, uint64 amount)
    {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Returns the total supply of the `token`.
    /// Reverts if the token does not exist or does not implement `totalSupply()`.
    function totalSupply(address token) internal view returns (uint64 result) {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// If the initial attempt fails, try to use Permit2 to transfer the token.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function safeTransferFrom2(address token, address from, address to, uint64 amount) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to` via Permit2.
    /// Reverts upon failure.
    function permit2TransferFrom(address token, address from, address to, uint64 amount)
        internal
    {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Permit a user to spend a given amount of
    /// another user's tokens via native EIP-2612 permit if possible, falling
    /// back to Permit2 if native permit fails or is not implemented on the token.
    function permit2(
        address token,
        address owner,
        address spender,
        uint64 amount,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Simple permit on the Permit2 contract.
    function simplePermit2(
        address token,
        address owner,
        address spender,
        uint64 amount,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Approves `spender` to spend `amount` of `token` for `address(this)`.
    function permit2Approve(address token, address spender, uint64 amount, uint64 expiration)
        internal
    {
        revert("ERC20 not supported on Solana, use SPL Token");
    }

    /// @dev Revokes an approval for `token` and `spender` for `address(this)`.
    function permit2Lockdown(address token, address spender) internal {
        revert("ERC20 not supported on Solana, use SPL Token");
    }
}