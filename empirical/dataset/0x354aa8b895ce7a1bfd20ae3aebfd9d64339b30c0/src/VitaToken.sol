// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;


/**

An on-chain life evolution experiment. 

https://vita.fun/
https://x.com/vitaoneth


*/


import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";


contract VitaToken is ERC20, ERC20Burnable {

    /// @notice Thrown when an unauthorized address attempts a hook-only operation.
    error OnlyHook();

    /// @notice Thrown when the hook address is the zero address.
    error ZeroHookAddress();

    /// @notice The address authorized to call `hookBurn` without prior approval (the hook contract).
    address public immutable hook;

    /// @notice Total supply: 10,000 tokens with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 10_000e18;

    /// @notice Deploys the Vita ERC-20 token with a fixed supply of 10,000 tokens.
    /// @dev    The entire supply is minted to `_recipient` at construction. The `_hook` address
    ///         is stored as an immutable and gains the ability to burn tokens without allowance,
    ///         which is critical for the seal mechanic.
    /// @param _hook      The Vita hook contract address, authorized to burn tokens on seal.
    /// @param _recipient The address that receives the full initial supply (typically the LP seed address).
    constructor(address _hook, address _recipient) ERC20("Vita", "VITA") {
        if (_hook == address(0)) revert ZeroHookAddress();
        hook = _hook;
        _mint(_recipient, TOTAL_SUPPLY);
    }

    /// @notice Burns tokens from a holder. Called by the hook when a pixel is sealed.
    /// @dev    Bypasses the ERC-20 allowance check when `msg.sender == hook`. This avoids
    ///         requiring the user to approve the hook before sealing. Reverts with `OnlyHook`
    ///         if called by any other address; standard `burnFrom` (inherited from ERC20Burnable)
    ///         remains available for approved callers.
    /// @param account The address to burn tokens from.
    /// @param amount  The amount of tokens to burn (expected: 1e18 per sealed pixel).
    function hookBurn(address account, uint256 amount) external {
        if (msg.sender != hook) revert OnlyHook();
        _burn(account, amount);
    }
}