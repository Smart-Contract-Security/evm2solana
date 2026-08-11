// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/interfaces/IAllowlist.sol";
import "contracts/interfaces/IAllowlistClient.sol";

abstract contract AllowlistClient is IAllowlistClient {
    // allowlist address
    IAllowlist public override allowlist;

    /**
    * @notice Constructor
    *
    * @param _allowlist Address of the allowlist contract
    */
    constructor(address _allowlist) {
        _setAllowlist(_allowlist);
    }

    /**
    * @notice Sets the allowlist address for this client
    *
    * @param _allowlist The new allowlist address
    */
    function _setAllowlist(address _allowlist) internal {
        if (_allowlist == address(0)) {
            revert AllowlistZeroAddress();
        }
        address oldAllowlist = address(allowlist);
        allowlist = IAllowlist(_allowlist);
        emit AllowlistSet(oldAllowlist, _allowlist);
    }

    /**
    * @notice Function to check if an account is allowed
    *
    * @param account The account to check
    */
    function isAllowed(address account) internal view returns (bool) {
        return allowlist.isAllowed(account);
    }
}
