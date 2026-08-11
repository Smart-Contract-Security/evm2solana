// SPDX-License-Identifier: MIT

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * NOTE: On Solana, value transfer via function calls is not supported.
     * This function is retained for API compatibility but will revert.
     */
    function sendValue(address payable recipient, uint64 amount) internal {
        revert("Address: sendValue not supported on Solana");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use `abi.decode`.
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * NOTE: On Solana, value transfer via function calls is not supported.
     * This function is retained for API compatibility but will revert if value > 0.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        if (value > 0) {
            revert("Address: value transfer not supported on Solana");
        }
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * NOTE: delegatecall is not available on Solana.
     * This function is retained for API compatibility but will revert.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        revert("Address: delegatecall not supported on Solana");
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // On Solana, address.code is not supported.
            // We skip the contract check and assume the call target is valid.
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // On Solana, mload is not available. Use abi.decode to extract the revert reason.
            // The revert data is expected to be the ABI-encoded string.
            // We simply revert with the raw bytes by using a low-level revert.
            // Since we cannot use assembly mload, we revert with the returndata directly.
            revert(string(returndata));
        } else {
            revert("Address: low-level call failed");
        }
    }
}