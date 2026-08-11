// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal burn surface used after internal buybacks and presale surplus allocation.
interface IBurnableToken {
    function burn(uint256 amount) external;
}
