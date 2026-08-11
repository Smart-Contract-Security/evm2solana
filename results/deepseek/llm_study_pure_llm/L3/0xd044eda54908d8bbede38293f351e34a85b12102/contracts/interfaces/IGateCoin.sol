// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Surface RushClaim reads from GateCoin.
 *
 *   - `spinReward(wallet)` is the canonical, on-chain implementation of
 *     S_i = unpack5(keccak256(wallet || SPIN_SEED)). It is `pure`, so the
 *     answer is fixed forever for any wallet + the immutable SPIN_SEED
 *     baked into the GateCoin bytecode. RushClaim calls this directly
 *     (no minter / no creditSpin trust) — no caller can inflate it.
 *
 *   - `balanceOf(wallet)` is the standard ERC-721 balance, used both as
 *     the K_nft input and as a "must have minted at least once" gate
 *     before materializing a spin credit.
 */
interface IGateCoin {
    function spinReward(address wallet) external pure returns (uint256);
    function balanceOf(address wallet) external view returns (uint256);
}