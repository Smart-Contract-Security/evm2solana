// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IECT is IERC20 {
    /// @notice Mint ECT. Restricted to the bonding curve.
    function mint(address to, uint256 amount) external;

    /// @notice Hard supply cap.
    function MAX_SUPPLY() external view returns (uint256);

    /// @notice Bonding curve address, set immutably at construction.
    function bondingCurve() external view returns (address);
}

interface IECTBurnable {
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}
