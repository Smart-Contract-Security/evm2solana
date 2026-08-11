// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

/// @title IHatToken
/// @notice $HAT ERC-20 — read interface + the two restricted mint paths.
///
/// Mint authority (whitepaper §07):
///   - Emitter (PrizeVault) for per-stage emissions
///   - HatCard for burn-to-mint
/// Burn is open to holders and to the swap-fee hook.
interface IHatToken {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);

    function mintEmission(address to, uint64 amount) external;
    function mintBurnToMint(address to, uint64 amount) external;
    function burn(uint64 amount) external;
    function burnFrom(address from, uint64 amount) external;
}