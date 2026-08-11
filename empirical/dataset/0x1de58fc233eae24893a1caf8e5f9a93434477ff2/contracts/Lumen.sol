// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title  Lumen (LMN)
 * @notice A minimal, fixed-supply ERC-20 token.
 *
 * DESIGN GOALS — minimal and safe:
 *   - No owner / no admin role.
 *   - No mint function after deployment: the supply is fixed forever.
 *   - No burn, no transfer tax, no pause, no blacklist, no upgrade path.
 *   - The ENTIRE supply is created once, inside the constructor, and sent
 *     to a single address that you choose.
 *
 * IMPORTANT — this contract has NOTHING to do with the Uniswap pool.
 *   It is just a plain token. Creating the Uniswap v4 pool and owning the
 *   liquidity position are handled entirely separately, by your own wallet.
 *   See the accompanying explanation for that flow.
 *
 * All real ERC-20 logic (transfer, approve, balanceOf, allowance, events,
 * 18 decimals) is inherited unchanged from OpenZeppelin's audited ERC20.
 * That is the "safe" part: this file adds as little new code as possible.
 */
contract Lumen is ERC20 {
    /// @notice The full token supply: 1,000,000 LMN.
    /// @dev    Expressed in base units. The token has 18 decimals, so the
    ///         human-readable "1,000,000" is 1_000_000 * 10**18 on-chain.
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    /**
     * @param recipient The address that receives the entire 1,000,000 LMN
     *                   supply at deployment time. Use your own wallet, or a
     *                   multisig you control. You will later move part of this
     *                   supply into the Uniswap v4 pool yourself.
     */
    constructor(address recipient) ERC20("Lumen", "LMN") {
        require(recipient != address(0), "Lumen: recipient is zero address");
        _mint(recipient, INITIAL_SUPPLY);
    }
}
