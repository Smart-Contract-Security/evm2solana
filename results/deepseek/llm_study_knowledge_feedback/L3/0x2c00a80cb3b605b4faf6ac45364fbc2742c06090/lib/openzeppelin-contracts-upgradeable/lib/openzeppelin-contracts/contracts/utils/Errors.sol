// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    uint64 constant InsufficientBalance = 1;

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    uint64 constant FailedCall = 2;

    /**
     * @dev The deployment failed.
     */
    uint64 constant FailedDeployment = 3;

    /**
     * @dev A necessary precompile is missing.
     */
    uint64 constant MissingPrecompile = 4;
}