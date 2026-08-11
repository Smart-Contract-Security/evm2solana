// SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITermRepoToken is IERC20 {
    function redemptionValue() external view returns (uint256);
    function totalRedemptionValue() external view returns (uint256);
    function burn(address account, uint256 amount) external;
    function burnAndReturnValue(address account, uint256 amount) external returns (uint256);
    function mintRedemptionValue(address account, uint256 redemptionAmount) external returns (uint256);
    function mintTokens(address account, uint256 numTokens) external returns (uint256);
    function decrementMintExposureCap(uint256 supplyMinted) external;
}