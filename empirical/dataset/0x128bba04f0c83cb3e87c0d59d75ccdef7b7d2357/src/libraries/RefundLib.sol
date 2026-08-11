// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "@interfaces/IERC20.sol";

library RefundLib {
    uint256 private constant ORIGIN_PAYER = 0x3ca20afc2ccc0000000000000000000000000000000000000000000000000000;
    uint256 private constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    /// @notice Extract the payer origin address from the last 32 bytes of calldata
    function getPayerOrigin() internal pure returns (address payerOriginAddr) {
        uint256 _payerOrigin;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let size := calldatasize()
            _payerOrigin := calldataload(sub(size, 32))
        }
        if ((_payerOrigin & ORIGIN_PAYER) == ORIGIN_PAYER) {
            payerOriginAddr = address(uint160(uint256(_payerOrigin) & ADDRESS_MASK));
        }
    }

    /// @notice Refund any remaining token dust to the payer origin
    function refund(address token) internal {
        address payerOrigin = getPayerOrigin();
        if (payerOrigin == address(0)) return;

        uint256 dust = IERC20(token).balanceOf(address(this));
        if (dust > 0) {
            SafeERC20.safeTransfer(IERC20(token), payerOrigin, dust);
        }
    }
}
