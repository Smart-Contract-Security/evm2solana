// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

/**
 * @title ICurveStablePool
 * @notice Minimal interface for Curve StableSwap-NG pools
 * @dev Used for NUSD/USDC price quotation via get_dy
 *
 *      NUSD/USDC Pool: 0x7E19F0253A564e026C63eeAA9338d6DBddeF3b09
 *      - Coin 0: NUSD (18 decimals)
 *      - Coin 1: USDC (6 decimals)
 *
 * @custom:reference https://www.curve.finance/dex/ethereum/pools/factory-stable-ng-595/swap
 */
interface ICurveStablePool {
    /// @notice Get the expected output amount for a swap
    /// @param i Index of input coin
    /// @param j Index of output coin
    /// @param dx Amount of input coin
    /// @return Expected amount of output coin
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    /// @notice Execute a swap
    /// @param i Index of input coin
    /// @param j Index of output coin
    /// @param dx Amount of input coin
    /// @param min_dy Minimum acceptable output
    /// @return Amount of output coin received
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);

    /// @notice EMA price oracle of `coins[i+1]` relative to `coins[0]` (1e18-scaled, decimal-normalised).
    /// @dev Updates lazily on every state-changing call (`exchange` / `add_liquidity` /
    ///      `remove_liquidity_imbalance`); the view function applies time-decay to the
    ///      stored EMA + `last_prices` so it returns the EMA "as of now" without state writes.
    ///
    ///      For a 2-coin pool, `i = 0` returns the EMA price of coins[1] in terms of coins[0].
    ///      The pool internally rate-normalises every coin to 1e18, so the returned value is
    ///      the exchange ratio AS IF both tokens were 18-decimal — use 1e18 as the conversion
    ///      scale regardless of raw token decimals.
    ///
    ///      Manipulation resistance is governed by the pool's `ma_exp_time` window; a single
    ///      block's swap can move the EMA by at most ~(blockTime / ma_exp_time).
    function price_oracle(uint256 i) external view returns (uint256);
}
