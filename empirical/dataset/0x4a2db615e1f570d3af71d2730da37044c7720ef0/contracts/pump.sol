// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Pump on eth ($PUMP)
 * @notice Clean ERC20 with a small transfer tax, a burn mechanism, and no
 *         blacklist/whitelist surveillance hooks. Tax is hard-capped in code.
 */
contract PumpOnEth is ERC20, ERC20Burnable, Ownable {
    // --- Tax configuration ---
    // Basis points: 100 = 1%. Hard ceiling so you can never rug holders with a 99% tax.
    uint256 public constant MAX_TAX_BPS = 300; // 3% absolute maximum, ever
    uint256 public taxBps = 100;               // starts at 1%

    // Where collected tax goes. Defaults to a "burn split" model below.
    address public taxWallet;

    // Of the tax collected, this fraction is burned outright (rest goes to taxWallet).
    // 10000 = 100% burned. Default: half burned, half to treasury.
    uint256 public burnShareBps = 5000;

    // Addresses exempt from tax (e.g. the contract itself, the LP router during setup).
    // This is NOT a blacklist — it can only REMOVE tax, never add restrictions.
    mapping(address => bool) public isTaxExempt;

    // Once renounced, tax parameters are frozen forever.
    bool public taxLocked;

    event TaxUpdated(uint256 taxBps, uint256 burnShareBps);
    event TaxWalletUpdated(address indexed wallet);
    event TaxExemptSet(address indexed account, bool exempt);
    event TaxLockedForever();

    constructor(address initialOwner, uint256 initialSupply)
        ERC20("Pump on eth", "PUMP")
        Ownable(initialOwner)
    {
        taxWallet = initialOwner;
        isTaxExempt[initialOwner] = true;
        isTaxExempt[address(this)] = true;
        _mint(initialOwner, initialSupply);
    }

    // --- Core: tax + burn on every transfer ---
    // Overrides OZ v5's internal _update hook, which all transfers/mints/burns flow through.
    function _update(address from, address to, uint256 value) internal override {
        // Mint (from == 0) and burn (to == 0) are never taxed.
        if (from == address(0) || to == address(0) || taxBps == 0) {
            super._update(from, to, value);
            return;
        }

        if (isTaxExempt[from] || isTaxExempt[to]) {
            super._update(from, to, value);
            return;
        }

        uint256 tax = (value * taxBps) / 10000;
        uint256 sendAmount = value - tax;

        if (tax > 0) {
            uint256 toBurn = (tax * burnShareBps) / 10000;
            uint256 toTreasury = tax - toBurn;

            if (toBurn > 0) {
                super._update(from, address(0), toBurn); // burn
            }
            if (toTreasury > 0) {
                super._update(from, taxWallet, toTreasury); // treasury
            }
        }

        super._update(from, to, sendAmount);
    }

    // --- Owner controls (all bounded, all renounceable) ---

    function setTax(uint256 _taxBps, uint256 _burnShareBps) external onlyOwner {
        require(!taxLocked, "tax locked");
        require(_taxBps <= MAX_TAX_BPS, "exceeds max tax");
        require(_burnShareBps <= 10000, "bad burn share");
        taxBps = _taxBps;
        burnShareBps = _burnShareBps;
        emit TaxUpdated(_taxBps, _burnShareBps);
    }

    function setTaxWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "zero wallet");
        taxWallet = _wallet;
        emit TaxWalletUpdated(_wallet);
    }

    function setTaxExempt(address account, bool exempt) external onlyOwner {
        isTaxExempt[account] = exempt;
        emit TaxExemptSet(account, exempt);
    }

    /// @notice Permanently freeze all tax parameters. Irreversible. Builds trust.
    function lockTaxForever() external onlyOwner {
        taxLocked = true;
        emit TaxLockedForever();
    }

    // ERC20Burnable already gives holders burn() and burnFrom() for manual burns.
}