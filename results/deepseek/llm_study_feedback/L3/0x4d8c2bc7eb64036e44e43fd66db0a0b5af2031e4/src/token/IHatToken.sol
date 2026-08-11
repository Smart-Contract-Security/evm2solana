// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IHatToken
/// @notice $HAT ERC-20 — read interface + the two restricted mint paths.
///
/// Mint authority (whitepaper §07):
///   - Emitter (PrizeVault) for per-stage emissions
///   - HatCard for burn-to-mint
/// Burn is open to holders and to the swap-fee hook.
interface IHatToken is IERC20 {
    function mintEmission(address to, uint256 amount) external;
    function mintBurnToMint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}