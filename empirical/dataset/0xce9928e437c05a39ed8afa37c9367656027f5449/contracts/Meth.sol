//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MiningEth is ERC20, Ownable {

    uint256 public constant MAX_SUPPLY = 42_000_000e18;

    uint256 public constant SEASON_ONE_MINING_REWARDS = 9_450_000e18;
    uint256 public constant TGE_LIQUIDITY_LAUNCH_RESERVE = 4_200_000e18;

    // Hard ceiling on tax in basis points (10% max). Immutable trust guarantee:
    // Cannot raise tax beyond this.
    uint16  public constant MAX_TAX_BPS = 1000;

    uint256 public amountBurned;

    // --- Tax / anti-snipe config ---
    mapping(address => bool) public isAMMPair;       // DEX pairs trigger buy/sell tax
    mapping(address => bool) public isFeeExempt;     // game contracts: full bypass
    mapping(address => bool) public isLimitExempt;   // bypass max-wallet only
    bool    public tradingEnabled;
    bool    public taxAuthorityRenounced;
    uint16  public buyTaxBps;
    uint16  public sellTaxBps;
    uint128 public maxWalletAmount;                  // 0 = disabled
    address public taxRecipient;

    event AMMPairSet(address indexed pair, bool isPair);
    event FeeExemptSet(address indexed account, bool exempt);
    event LimitExemptSet(address indexed account, bool exempt);
    event TaxesSet(uint16 buyBps, uint16 sellBps);
    event MaxWalletSet(uint128 amount);
    event TaxRecipientSet(address indexed recipient);
    event TradingEnabled();
    event TaxAuthorityRenounced();

    error TradingNotEnabled();
    error MaxWalletExceeded();
    error TaxTooHigh();
    error AuthorityRenounced();
    error ZeroAddress();

    constructor(address _lpAddress, address _tokenDistributorAddress, address _treasury) ERC20("Mining Eth", "METH") Ownable(msg.sender) {
        uint256 treasuryAllocation = MAX_SUPPLY - (SEASON_ONE_MINING_REWARDS + TGE_LIQUIDITY_LAUNCH_RESERVE);
        _mint(_lpAddress, TGE_LIQUIDITY_LAUNCH_RESERVE); // TGE liquidity launch reserve
        _mint(_tokenDistributorAddress, SEASON_ONE_MINING_REWARDS); // Season one mining rewards
        _mint(_treasury, treasuryAllocation);

        // Auto-exempt initial mint recipients and deployer. Game contracts that
        // are not yet deployed (system / market / converter) get exempted later
        // by the deploy script via setFeeExempt / setLimitExempt.
        isFeeExempt[_lpAddress] = true;
        isFeeExempt[_tokenDistributorAddress] = true;
        isFeeExempt[_treasury] = true;
        isFeeExempt[msg.sender] = true;
        isLimitExempt[_lpAddress] = true;
        isLimitExempt[_tokenDistributorAddress] = true;
        isLimitExempt[_treasury] = true;
        isLimitExempt[msg.sender] = true;

        taxRecipient = _treasury;
    }

    function burn(uint256 value) external {
        amountBurned += value;
        _burn(_msgSender(), value);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Transfer hook — tax + anti-snipe enforcement
    // ─────────────────────────────────────────────────────────────────

    function _update(address from, address to, uint256 value) internal override {
        // Mint / burn always pass.
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Exempt side - no tax, no limits, no trading gate. This is what
        // keeps every game-contract METH flow tax-free regardless of state.
        if (isFeeExempt[from] || isFeeExempt[to]) {
            super._update(from, to, value);
            return;
        }

        if (!tradingEnabled) revert TradingNotEnabled();

        uint256 bps;
        if (isAMMPair[from])      bps = buyTaxBps;   // buy from pair
        else if (isAMMPair[to])   bps = sellTaxBps;  // sell into pair

        if (bps != 0) {
            uint256 fee = (value * bps) / 10_000;
            if (fee != 0) {
                super._update(from, taxRecipient, fee);
                value -= fee;
            }
        }

        // Max-wallet enforced on buys only (pair - user).
        if (isAMMPair[from] && !isLimitExempt[to] && maxWalletAmount != 0) {
            if (balanceOf(to) + value > maxWalletAmount) revert MaxWalletExceeded();
        }

        super._update(from, to, value);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Owner controls
    // ─────────────────────────────────────────────────────────────────

    function setAMMPair(address pair, bool v) external onlyOwner {
        if (pair == address(0)) revert ZeroAddress();
        isAMMPair[pair] = v;
        emit AMMPairSet(pair, v);
    }

    function setFeeExempt(address account, bool v) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        isFeeExempt[account] = v;
        emit FeeExemptSet(account, v);
    }

    function setLimitExempt(address account, bool v) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        isLimitExempt[account] = v;
        emit LimitExemptSet(account, v);
    }

    function setTaxes(uint16 buyBps, uint16 sellBps) external onlyOwner {
        if (taxAuthorityRenounced) revert AuthorityRenounced();
        if (buyBps > MAX_TAX_BPS || sellBps > MAX_TAX_BPS) revert TaxTooHigh();
        buyTaxBps = buyBps;
        sellTaxBps = sellBps;
        emit TaxesSet(buyBps, sellBps);
    }

    function setMaxWallet(uint128 amount) external onlyOwner {
        if (taxAuthorityRenounced) revert AuthorityRenounced();
        maxWalletAmount = amount;
        emit MaxWalletSet(amount);
    }

    function setTaxRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        taxRecipient = recipient;
        emit TaxRecipientSet(recipient);
    }

    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice One-way switch. Permanently zeroes all taxes and limits and
    ///         locks them so no future owner can ever re-enable them.
    function renounceTaxAuthority() external onlyOwner {
        buyTaxBps = 0;
        sellTaxBps = 0;
        maxWalletAmount = 0;
        taxAuthorityRenounced = true;
        emit TaxAuthorityRenounced();
    }
}
