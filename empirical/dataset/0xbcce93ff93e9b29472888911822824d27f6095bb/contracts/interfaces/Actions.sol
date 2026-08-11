// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Action constants for Uniswap V4 PositionManager & Universal Router
/// @dev Values from official v4-periphery/src/libraries/Actions.sol
library Actions {
    // ----- Liquidity actions -----
    uint256 internal constant INCREASE_LIQUIDITY            = 0x00;
    uint256 internal constant DECREASE_LIQUIDITY            = 0x01;
    uint256 internal constant MINT_POSITION                 = 0x02;
    uint256 internal constant BURN_POSITION                 = 0x03;
    uint256 internal constant INCREASE_LIQUIDITY_FROM_DELTAS = 0x04;
    uint256 internal constant MINT_POSITION_FROM_DELTAS     = 0x05;

    // ----- Swap actions (Universal Router V4_SWAP) -----
    uint256 internal constant SWAP_EXACT_IN_SINGLE          = 0x06;
    uint256 internal constant SWAP_EXACT_IN                 = 0x07;
    uint256 internal constant SWAP_EXACT_OUT_SINGLE         = 0x08;
    uint256 internal constant SWAP_EXACT_OUT                = 0x09;

    // ----- Donate -----
    uint256 internal constant DONATE                        = 0x0a;

    // ----- Settlement actions -----
    uint256 internal constant SETTLE                        = 0x0b;
    uint256 internal constant SETTLE_ALL                    = 0x0c;
    uint256 internal constant SETTLE_PAIR                   = 0x0d;
    uint256 internal constant TAKE                          = 0x0e;
    uint256 internal constant TAKE_ALL                      = 0x0f;
    uint256 internal constant TAKE_PORTION                  = 0x10;
    uint256 internal constant TAKE_PAIR                     = 0x11;
    uint256 internal constant CLOSE_CURRENCY                = 0x12;
    uint256 internal constant CLEAR_OR_TAKE                 = 0x13;
    uint256 internal constant SWEEP                         = 0x14;

    // ----- Wrapping -----
    uint256 internal constant WRAP                          = 0x15;
    uint256 internal constant UNWRAP                        = 0x16;

    // ----- ERC6909 -----
    uint256 internal constant MINT_6909                     = 0x17;
    uint256 internal constant BURN_6909                     = 0x18;
}
