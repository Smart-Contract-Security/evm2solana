// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title  NYX — the public, tradeable Nyxora coin
/// @notice Plain fixed-supply ERC-20 (no transfer tax — the 1% buy/sell tax lives in the
///         Uniswap V4 hook). At launch it carries a **max-wallet cap** (anti-whale / anti-bot)
///         that the owner can lift once forever with `removeLimits()`.
/// @dev    Exempt the pool, router, wrapper (cNYX) and treasury so liquidity + wrapping work.
///         Hold it privately by wrapping NYX → cNYX (a ConfidentialVault, ERC-7984).
///         (Foundry copy of contracts/NYX.sol — pragma relaxed to ^0.8.26 to match the hooks build.)
contract NYX is ERC20, ERC20Permit, Ownable2Step {
    bool public limitsActive = true;
    uint256 public maxWallet;
    mapping(address => bool) public isExempt;

    event LimitsRemoved();
    event ExemptSet(address indexed account, bool exempt);
    event MaxWalletSet(uint256 maxWallet);

    error MaxWalletExceeded();
    error MaxWalletTooLow();
    error LimitsAlreadyLifted();

    constructor(
        address treasury,
        uint256 supply,
        address owner_
    ) ERC20("Nyxora", "NYX") ERC20Permit("Nyxora") Ownable(owner_) {
        maxWallet = supply / 50; // 2% of supply at launch
        isExempt[treasury] = true;
        isExempt[owner_] = true;
        _mint(treasury, supply);
        emit MaxWalletSet(maxWallet);
    }

    function setExempt(address account, bool exempt) external onlyOwner {
        if (!limitsActive) revert LimitsAlreadyLifted();
        isExempt[account] = exempt;
        emit ExemptSet(account, exempt);
    }

    function setMaxWallet(uint256 newMax) external onlyOwner {
        if (newMax < totalSupply() / 1000) revert MaxWalletTooLow();
        maxWallet = newMax;
        emit MaxWalletSet(newMax);
    }

    function removeLimits() external onlyOwner {
        limitsActive = false;
        emit LimitsRemoved();
    }

    function _update(address from, address to, uint256 value) internal override {
        if (limitsActive && to != address(0) && !isExempt[to]) {
            if (balanceOf(to) + value > maxWallet) revert MaxWalletExceeded();
        }
        super._update(from, to, value);
    }
}
