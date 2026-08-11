// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { SignedPriceBundle } from "./Types.sol";


interface IERC7575 is IERC165 {
    /// @notice 返回该 Vault 对应的外部 ShareToken。
    function share() external view returns (address shareTokenAddress);
    function asset() external view returns (address assetTokenAddress);
    function totalAssets() external view returns (uint256 totalManagedAssets);
    function convertToShares(uint256 assets, SignedPriceBundle calldata priceBundle) external view returns (uint256 shares);
    function convertToAssets(uint256 shares, SignedPriceBundle calldata priceBundle) external view returns (uint256 assets);
}
