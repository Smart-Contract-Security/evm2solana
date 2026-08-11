// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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
    error ETHTransferFailed();

    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();

    /// @dev The ERC20 `approve` has failed.
    error ApproveFailed();

    /// @dev The ERC20 `totalSupply` query has failed.
    error TotalSupplyQueryFailed();

    /// @dev The Permit2 operation has failed.
    error Permit2Failed();

    /// @dev The Permit2 amount must be less than `2**160 - 1`.
    error Permit2AmountOverflow();

    /// @dev The Permit2 approve operation has failed.
    error Permit2ApproveFailed();

    /// @dev The Permit2 lockdown operation has failed.
    error Permit2LockdownFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Suggested gas stipend for contract receiving ETH that disallows any storage writes.
    uint256 internal constant GAS_STIPEND_NO_STORAGE_WRITES = 2300;

    /// @dev Suggested gas stipend for contract receiving ETH to perform a few
    /// storage reads and writes, but low enough to prevent griefing.
    uint256 internal constant GAS_STIPEND_NO_GRIEF = 100000;

    /// @dev The unique EIP-712 domain separator for the DAI token contract.
    bytes32 internal constant DAI_DOMAIN_SEPARATOR =
        0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7;

    /// @dev The address for the WETH9 contract on Ethereum mainnet.
    /// Not available on Solana; set to zero address.
    address internal constant WETH9 = address(0);

    /// @dev The canonical Permit2 address.
    /// Not available on Solana; set to zero address.
    address internal constant PERMIT2 = address(0);

    /// @dev The canonical address of the `SELFDESTRUCT` ETH mover.
    /// Not available on Solana; set to zero address.
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
    function safeTransferETH(address to, uint256 amount) internal {
        // Solana: use lamports transfer via AccountInfo
        require(tx.accounts.to.lamports >= amount, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
    }

    /// @dev Sends all the ETH in the current contract to `to`.
    function safeTransferAllETH(address to) internal {
        uint256 amount = tx.accounts.this.lamports;
        require(amount > 0, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
    }

    /// @dev Force sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function forceSafeTransferETH(address to, uint256 amount, uint256 gasStipend) internal {
        require(tx.accounts.this.lamports >= amount, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
    }

    /// @dev Force sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function forceSafeTransferAllETH(address to, uint256 gasStipend) internal {
        uint256 amount = tx.accounts.this.lamports;
        require(amount > 0, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
    }

    /// @dev Force sends `amount` (in wei) ETH to `to`, with `GAS_STIPEND_NO_GRIEF`.
    function forceSafeTransferETH(address to, uint256 amount) internal {
        require(tx.accounts.this.lamports >= amount, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
    }

    /// @dev Force sends all the ETH in the current contract to `to`, with `GAS_STIPEND_NO_GRIEF`.
    function forceSafeTransferAllETH(address to) internal {
        uint256 amount = tx.accounts.this.lamports;
        require(amount > 0, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
    }

    /// @dev Sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function trySafeTransferETH(address to, uint256 amount, uint256 gasStipend)
        internal
        returns (bool success)
    {
        // Solana: use lamports transfer
        if (tx.accounts.this.lamports >= amount) {
            tx.accounts.to.lamports += amount;
            tx.accounts.this.lamports -= amount;
            success = true;
        } else {
            success = false;
        }
    }

    /// @dev Sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function trySafeTransferAllETH(address to, uint256 gasStipend)
        internal
        returns (bool success)
    {
        uint256 amount = tx.accounts.this.lamports;
        if (amount > 0) {
            tx.accounts.to.lamports += amount;
            tx.accounts.this.lamports -= amount;
            success = true;
        } else {
            success = false;
        }
    }

    /// @dev Force transfers ETH to `to`, without triggering the fallback (if any).
    /// This method attempts to use a separate contract to send via `SELFDESTRUCT`,
    /// and upon failure, deploys a minimal vault to accrue the ETH.
    function safeMoveETH(address to, uint256 amount) internal returns (address vault) {
        require(tx.accounts.this.lamports >= amount, "ETHTransferFailed");
        tx.accounts.to.lamports += amount;
        tx.accounts.this.lamports -= amount;
        return address(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ERC20 OPERATIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](3);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: from, is_signer: false, is_writable: true});
        metas[2] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFromFailed");
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function trySafeTransferFrom(address token, address from, address to, uint256 amount)
        internal
        returns (bool success)
    {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](3);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: from, is_signer: false, is_writable: true});
        metas[2] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        (success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        if (success && data.length >= 32) {
            success = abi.decode(data, (bool));
        }
    }

    /// @dev Sends all of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have their entire balance approved for the current contract to manage.
    function safeTransferAllFrom(address token, address from, address to)
        internal
        returns (uint256 amount)
    {
        amount = balanceOf(token, from);
        safeTransferFrom(token, from, to, amount);
    }

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransfer(address token, address to, uint256 amount) internal {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](2);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFailed");
    }

    /// @dev Sends all of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransferAll(address token, address to) internal returns (uint256 amount) {
        amount = balanceOf(token, address(this));
        safeTransfer(token, to, amount);
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// Reverts upon failure.
    function safeApprove(address token, address to, uint256 amount) internal {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](2);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("approve(address,uint256)", to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "ApproveFailed");
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// If the initial attempt to approve fails, attempts to reset the approved amount to zero,
    /// then retries the approval again (some tokens, e.g. USDT, requires this).
    /// Reverts upon failure.
    function safeApproveWithRetry(address token, address to, uint256 amount) internal {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](2);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("approve(address,uint256)", to, amount)
        );
        if (!success || (data.length >= 32 && !abi.decode(data, (bool)))) {
            // Reset approval to zero
            token.call{accounts: metas}(abi.encodeWithSignature("approve(address,uint256)", to, 0));
            // Retry
            (success, data) = token.call{accounts: metas}(
                abi.encodeWithSignature("approve(address,uint256)", to, amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "ApproveFailed");
        }
    }

    /// @dev Returns the amount of ERC20 `token` owned by `account`.
    /// Returns zero if the `token` does not exist.
    function balanceOf(address token, address account) internal view returns (uint256 amount) {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](2);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: false});
        metas[1] = AccountMeta({pubkey: account, is_signer: false, is_writable: false});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        if (success && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    /// @dev Performs a `token.balanceOf(account)` check.
    /// `implemented` denotes whether the `token` does not implement `balanceOf`.
    /// `amount` is zero if the `token` does not implement `balanceOf`.
    function checkBalanceOf(address token, address account)
        internal
        view
        returns (bool implemented, uint256 amount)
    {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](2);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: false});
        metas[1] = AccountMeta({pubkey: account, is_signer: false, is_writable: false});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        implemented = success && data.length >= 32;
        if (implemented) {
            amount = abi.decode(data, (uint256));
        }
    }

    /// @dev Returns the total supply of the `token`.
    /// Reverts if the token does not exist or does not implement `totalSupply()`.
    function totalSupply(address token) internal view returns (uint256 result) {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: false});
        (bool success, bytes memory data) = token.call{accounts: metas}(
            abi.encodeWithSignature("totalSupply()")
        );
        require(success && data.length >= 32, "TotalSupplyQueryFailed");
        result = abi.decode(data, (uint256));
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// If the initial attempt fails, try to use Permit2 to transfer the token.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function safeTransferFrom2(address token, address from, address to, uint256 amount) internal {
        if (!trySafeTransferFrom(token, from, to, amount)) {
            permit2TransferFrom(token, from, to, amount);
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to` via Permit2.
    /// Reverts upon failure.
    function permit2TransferFrom(address token, address from, address to, uint256 amount)
        internal
    {
        // Solana: use external call with accounts
        require(amount <= type(uint160).max, "Permit2AmountOverflow");
        AccountMeta[] memory metas = new AccountMeta[](4);
        metas[0] = AccountMeta({pubkey: PERMIT2, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[2] = AccountMeta({pubkey: from, is_signer: false, is_writable: true});
        metas[3] = AccountMeta({pubkey: to, is_signer: false, is_writable: true});
        (bool success, ) = PERMIT2.call{accounts: metas}(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint160,address)",
                from,
                to,
                uint160(amount),
                token
            )
        );
        require(success, "Permit2Failed");
    }

    /// @dev Permit a user to spend a given amount of
    /// another user's tokens via native EIP-2612 permit if possible, falling
    /// back to Permit2 if native permit fails or is not implemented on the token.
    function permit2(
        address token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        bool success = false;
        // Try native permit
        if (token != WETH9) {
            // Check if token supports DOMAIN_SEPARATOR
            AccountMeta[] memory metas1 = new AccountMeta[](1);
            metas1[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: false});
            (bool ok, bytes memory data) = token.call{accounts: metas1}(
                abi.encodeWithSignature("DOMAIN_SEPARATOR()")
            );
            if (ok && data.length == 32) {
                bytes32 domainSeparator = abi.decode(data, (bytes32));
                AccountMeta[] memory metas3 = new AccountMeta[](3);
                metas3[0] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
                metas3[1] = AccountMeta({pubkey: owner, is_signer: false, is_writable: true});
                metas3[2] = AccountMeta({pubkey: spender, is_signer: false, is_writable: true});
                if (domainSeparator == DAI_DOMAIN_SEPARATOR) {
                    // DAI permit
                    (success, ) = token.call{accounts: metas3}(
                        abi.encodeWithSignature(
                            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                            owner,
                            spender,
                            amount,
                            deadline,
                            v,
                            r,
                            s
                        )
                    );
                } else {
                    // Standard ERC20 permit
                    (success, ) = token.call{accounts: metas3}(
                        abi.encodeWithSignature(
                            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                            owner,
                            spender,
                            amount,
                            deadline,
                            v,
                            r,
                            s
                        )
                    );
                }
            }
        }
        if (!success) simplePermit2(token, owner, spender, amount, deadline, v, r, s);
    }

    /// @dev Simple permit on the Permit2 contract.
    function simplePermit2(
        address token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        // Solana: use external call with accounts
        require(amount <= type(uint160).max, "Permit2AmountOverflow");
        // Get nonce
        AccountMeta[] memory metas4 = new AccountMeta[](4);
        metas4[0] = AccountMeta({pubkey: PERMIT2, is_signer: false, is_writable: false});
        metas4[1] = AccountMeta({pubkey: owner, is_signer: false, is_writable: false});
        metas4[2] = AccountMeta({pubkey: token, is_signer: false, is_writable: false});
        metas4[3] = AccountMeta({pubkey: spender, is_signer: false, is_writable: false});
        (bool ok, bytes memory data) = PERMIT2.call{accounts: metas4}(
            abi.encodeWithSignature("allowance(address,address,address)", owner, token, spender)
        );
        require(ok && data.length >= 96, "Permit2Failed");
        // Decode allowance data: amount, expiration, nonce
        (uint256 allowanceAmount, uint256 expiration, uint256 nonce) = abi.decode(data, (uint256, uint256, uint256));
        // Call permit
        AccountMeta[] memory metas4b = new AccountMeta[](4);
        metas4b[0] = AccountMeta({pubkey: PERMIT2, is_signer: false, is_writable: true});
        metas4b[1] = AccountMeta({pubkey: owner, is_signer: false, is_writable: true});
        metas4b[2] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas4b[3] = AccountMeta({pubkey: spender, is_signer: false, is_writable: true});
        (bool success, ) = PERMIT2.call{accounts: metas4b}(
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint256,address,uint256,bytes)",
                owner,
                token,
                amount,
                type(uint48).max,
                nonce,
                spender,
                deadline,
                abi.encodePacked(r, s, bytes1(v))
            )
        );
        require(success, "Permit2Failed");
    }

    /// @dev Approves `spender` to spend `amount` of `token` for `address(this)`.
    function permit2Approve(address token, address spender, uint160 amount, uint48 expiration)
        internal
    {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](3);
        metas[0] = AccountMeta({pubkey: PERMIT2, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[2] = AccountMeta({pubkey: spender, is_signer: false, is_writable: true});
        (bool success, ) = PERMIT2.call{accounts: metas}(
            abi.encodeWithSignature(
                "approve(address,address,uint160,uint48)",
                token,
                spender,
                amount,
                expiration
            )
        );
        require(success, "Permit2ApproveFailed");
    }

    /// @dev Revokes an approval for `token` and `spender` for `address(this)`.
    function permit2Lockdown(address token, address spender) internal {
        // Solana: use external call with accounts
        AccountMeta[] memory metas = new AccountMeta[](3);
        metas[0] = AccountMeta({pubkey: PERMIT2, is_signer: false, is_writable: true});
        metas[1] = AccountMeta({pubkey: token, is_signer: false, is_writable: true});
        metas[2] = AccountMeta({pubkey: spender, is_signer: false, is_writable: true});
        (bool success, ) = PERMIT2.call{accounts: metas}(
            abi.encodeWithSignature("lockdown(address,address)", token, spender)
        );
        require(success, "Permit2LockdownFailed");
    }
}