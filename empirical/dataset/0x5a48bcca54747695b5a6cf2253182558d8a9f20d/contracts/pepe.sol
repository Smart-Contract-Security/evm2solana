// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PepeThePenguin is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1e9 * 1e18

    uint256 public maxTransactionAmount;
    uint256 public maxWalletAmount;

    bool public tradingEnabled;
    bool public limitsEnabled = true;

    // Addresses that ignore limits + trading gate (owner, contract, router, position manager).
    mapping(address => bool) public isExcludedFromLimits;
    // AMM pairs/pools. A `to` that is an AMM pair is a SELL/add-liquidity, so maxWallet is not applied to it.
    mapping(address => bool) public isAMMPair;

    event TradingEnabled();
    event LimitsRemoved();
    event LimitsUpdated(uint256 maxTransactionAmount, uint256 maxWalletAmount);
    event AMMPairSet(address indexed pair, bool value);
    event ExcludedFromLimits(address indexed account, bool value);

    constructor() ERC20("Pepe The Penguin", "PEPE") Ownable(msg.sender) {
        maxTransactionAmount = (TOTAL_SUPPLY * 5) / 1000; // 0.5%
        maxWalletAmount = (TOTAL_SUPPLY * 2) / 100; // 2%

        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[address(0)] = true;
        isExcludedFromLimits[0x000000000000000000000000000000000000dEaD] = true;

        _mint(msg.sender, TOTAL_SUPPLY);
    }

    // --- Owner controls ---------------------------------------------------

    function startWaddle() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice Register/unregister a Uniswap V3 pool (or any AMM pair) for limit handling.
    function setFishingHole(address pair, bool value) external onlyOwner {
        require(pair != address(0), "Zero pair");
        isAMMPair[pair] = value;
        emit AMMPairSet(pair, value);
    }

    function excludeFromIce(address account, bool value) external onlyOwner {
        isExcludedFromLimits[account] = value;
        emit ExcludedFromLimits(account, value);
    }

    /// @notice Adjust limits. Values are in whole tokens (e.g. 5_000_000), converted to wei here.
    function carveIce(uint256 maxTxTokens, uint256 maxWalletTokens) external onlyOwner {
        uint256 newMaxTx = maxTxTokens * 1e18;
        uint256 newMaxWallet = maxWalletTokens * 1e18;
        // Guardrails: never below 0.1% to avoid bricking the token.
        require(newMaxTx >= (TOTAL_SUPPLY * 1) / 1000, "maxTx too low");
        require(newMaxWallet >= (TOTAL_SUPPLY * 1) / 1000, "maxWallet too low");
        maxTransactionAmount = newMaxTx;
        maxWalletAmount = newMaxWallet;
        emit LimitsUpdated(newMaxTx, newMaxWallet);
    }

    /// @notice Permanently lift max tx / max wallet limits (one-way).
    function meltIce() external onlyOwner {
        limitsEnabled = false;
        emit LimitsRemoved();
    }

    // --- Transfer hook (OZ v5) -------------------------------------------

    function _update(address from, address to, uint256 amount) internal override {
        // Minting (from == 0) and burning to dead are always allowed.
        bool excluded = isExcludedFromLimits[from] || isExcludedFromLimits[to];

        if (!excluded) {
            require(tradingEnabled, "Trading not enabled");

            if (limitsEnabled) {
                // Max transaction applies to both buys and sells.
                require(amount <= maxTransactionAmount, "Exceeds max transaction");

                // Max wallet applies when receiver is a normal wallet (buy or wallet-to-wallet),
                // not when sending into an AMM pair (sell / add liquidity).
                if (!isAMMPair[to]) {
                    require(balanceOf(to) + amount <= maxWalletAmount, "Exceeds max wallet");
                }
            }
        }

        super._update(from, to, amount);
    }
}
