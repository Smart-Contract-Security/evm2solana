// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// https://x.com/PepeByDon
// https://www.reddit.com/r/KotakuInAction/comments/71anp1/matt_furie_may_have_plagiarised_the_design_of/

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Pepe By Don R. Christensen
 * @notice Standard ERC20 (10,000,000 supply) with launch protections:
 *         - trading gate (owner must explicitly enable trading)
 *         - max transaction = 0.25% of supply
 *         - max wallet      = 2% of supply
 *
 *  Limit logic mirrors the well-worn meme-token pattern:
 *   - `isExcludedFromLimits` addresses (owner, this contract) bypass everything,
 *     which is how the owner seeds liquidity before trading is live.
 *   - `isAMMPair` addresses (the Uniswap V3 pool) are exempt from max-wallet ONLY,
 *     so the pool can hold the full liquidity float while buys/sells stay capped.
 */
contract PepeByDonRChristensen is ERC20, Ownable {
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;
    bool public tradingEnabled;
    bool public limitsEnabled = true;

    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public isAMMPair;

    event TradingEnabled();
    event LimitsRemoved();
    event ExcludedFromLimits(address indexed account, bool excluded);
    event AMMPairSet(address indexed pair, bool value);
    event MaxTxAmountUpdated(uint256 amount);
    event MaxWalletAmountUpdated(uint256 amount);

    constructor() ERC20("Pepe By Don R. Christensen", "PEPE") Ownable(msg.sender) {
        uint256 supply = 10_000_000 * 10 ** decimals();

        maxTxAmount = (supply * 25) / 10_000; // 0.25%
        maxWalletAmount = (supply * 200) / 10_000; // 2%

        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;

        _mint(msg.sender, supply);
    }

    // --------------------------------------------------------------------- //
    //                              Owner controls                           //
    // --------------------------------------------------------------------- //

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice Lift both max-tx and max-wallet caps permanently.
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        emit LimitsRemoved();
    }

    function setExcludedFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
        emit ExcludedFromLimits(account, excluded);
    }

    function setAMMPair(address pair, bool value) external onlyOwner {
        isAMMPair[pair] = value;
        emit AMMPairSet(pair, value);
    }

    function setMaxTxAmount(uint256 amount) external onlyOwner {
        require(amount >= (totalSupply() * 1) / 10_000, "Max tx too low"); // >= 0.01%
        maxTxAmount = amount;
        emit MaxTxAmountUpdated(amount);
    }

    function setMaxWalletAmount(uint256 amount) external onlyOwner {
        require(amount >= (totalSupply() * 1) / 1_000, "Max wallet too low"); // >= 0.1%
        maxWalletAmount = amount;
        emit MaxWalletAmountUpdated(amount);
    }

    // --------------------------------------------------------------------- //
    //                          Transfer hook (OZ v5)                        //
    // --------------------------------------------------------------------- //

    function _update(address from, address to, uint256 value) internal override {
        // Skip checks on mint (from == 0) and burn (to == 0).
        if (from != address(0) && to != address(0)) {
            bool exempt = isExcludedFromLimits[from] || isExcludedFromLimits[to];

            if (!exempt) {
                require(tradingEnabled, "Trading not enabled");

                if (limitsEnabled) {
                    require(value <= maxTxAmount, "Exceeds max tx");
                    // Pools (AMM pairs) may exceed max wallet; ordinary holders may not.
                    if (!isAMMPair[to]) {
                        require(balanceOf(to) + value <= maxWalletAmount, "Exceeds max wallet");
                    }
                }
            }
        }

        super._update(from, to, value);
    }
}
