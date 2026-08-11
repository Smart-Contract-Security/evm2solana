// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// website: https://www.vitalikbuterin.io/
// X/Twitter: https://x.com/vitalikmemecoin
// Telegram: https://t.me/vitalikerc20

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/**
 * @title VITALIK
 * @notice Fixed-supply ERC20 with Uniswap V2 launch mechanics:
 *         - 0.25% max transaction, 2% max wallet (removable, one-way)
 *         - 19/29 buy/sell tax for the first 400 buys, then a low final rate
 *         - one-way trading enable (selling can NEVER be re-paused once live)
 *         - tax setters hard-capped (owner cannot create a high-tax soft honeypot)
 *         - no mint; NO owner-controlled blacklist or freeze
 *
 *         LOCKED_HOLDER: exactly one address (Vitalik's) is hardcoded as a
 *         compile-time constant whose tokens can never be transferred out. It
 *         is immutable — there is no setter and it can never be changed or
 *         extended to any other address, so no buyer can ever be frozen. Tokens
 *         sent to it are permanently locked (a transparent, verifiable soft-burn).
 *
 *         Ownership is renounceable via Ownable.renounceOwnership().
 */
contract VitalikToken is ERC20, Ownable {
    IUniswapV2Router02 public immutable router;
    address public immutable uniswapPair;
    address public taxWallet;

    /// @notice Vitalik's address. Tokens sent here are PERMANENTLY locked: this
    /// address can receive but can never transfer/sell. Hardcoded constant, no
    /// setter, immutable — applies ONLY to this address and cannot be changed
    /// or extended to anyone else. No buyer can ever be locked.
    address public constant LOCKED_HOLDER = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;

    bool public tradingEnabled;
    bool public limitsInEffect = true;

    uint256 public maxTx;
    uint256 public maxWallet;
    uint256 public swapThreshold;

    // taxes are tier-driven by buy count; no arbitrary owner toggle of selling
    uint256 public constant MAX_TAX = 25; // hard ceiling — owner can never exceed
    uint256 public buyTaxInitial = 19;
    uint256 public sellTaxInitial = 29;
    uint256 public buyTaxFinal = 0;
    uint256 public sellTaxFinal = 0;
    uint256 public reduceTaxAt = 400;
    uint256 public buyCount;

    bool private inSwap;
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;

    event TradingEnabled();
    event LimitsRemoved();
    event FinalTaxesUpdated(uint256 buyTax, uint256 sellTax);
    event TaxWalletUpdated(address wallet);

    modifier lockSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address router_, address taxWallet_)
        ERC20("Vitalik", "VITALIK")
        Ownable(msg.sender)
    {
        require(router_ != address(0) && taxWallet_ != address(0), "zero addr");
        router = IUniswapV2Router02(router_);
        uniswapPair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());
        taxWallet = taxWallet_;

        uint256 supply = 120_685_461 * 10 ** decimals(); // matches ETH total supply
        maxTx = (supply * 25) / 10000; // 0.25%
        maxWallet = (supply * 200) / 10000; // 2%
        swapThreshold = (supply * 5) / 10000; // 0.05% — accrued-tax swap trigger

        isExcludedFromFees[msg.sender] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[taxWallet_] = true;
        isExcludedFromFees[router_] = true;

        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[taxWallet_] = true;
        isExcludedFromLimits[router_] = true;
        isExcludedFromLimits[uniswapPair] = true;

        // Genesis distribution, all minted directly (no post-deploy transfers):
        //   5%  -> the contract ("clog", drains to ETH via tax swaps)
        //   50% -> LOCKED_HOLDER (Vitalik) — permanently locked from block 0
        //   45% -> deployer (for the Uniswap LP)
        uint256 clog = (supply * 5) / 100;
        uint256 locked = (supply * 50) / 100;
        _mint(address(this), clog);
        _mint(LOCKED_HOLDER, locked);
        _mint(msg.sender, supply - clog - locked);
    }

    // ── owner controls (intentionally limited; nothing here can trap holders) ──

    /// @notice Turn on trading. One-way: once enabled it can never be disabled.
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice Drop the per-tx / per-wallet caps. One-way.
    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        emit LimitsRemoved();
    }

    /// @notice Adjust the post-400-buys tax. Hard-capped by MAX_TAX so this can
    ///         never be used to choke selling. Initial launch taxes are fixed.
    function setFinalTaxes(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        require(newBuyTax <= MAX_TAX && newSellTax <= MAX_TAX, "tax too high");
        buyTaxFinal = newBuyTax;
        sellTaxFinal = newSellTax;
        emit FinalTaxesUpdated(newBuyTax, newSellTax);
    }

    function setTaxWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "zero addr");
        taxWallet = wallet;
        isExcludedFromFees[wallet] = true;
        isExcludedFromLimits[wallet] = true;
        emit TaxWalletUpdated(wallet);
    }

    function setExcludedFromFees(address account, bool excluded) external onlyOwner {
        isExcludedFromFees[account] = excluded;
    }

    function setExcludedFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    /// @notice Manually convert accrued tax tokens to ETH for the tax wallet.
    function manualSwap() external onlyOwner {
        uint256 bal = balanceOf(address(this));
        require(bal > 0, "nothing to swap");
        _swapBack(bal);
    }

    /// @notice Rescue ETH accidentally sent to the contract.
    function rescueETH() external onlyOwner {
        (bool ok, ) = payable(taxWallet).call{value: address(this).balance}("");
        require(ok, "eth send failed");
    }

    /// @notice Rescue a foreign token sent to the contract (never the native $VITALIK).
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(this), "no native rescue");
        IERC20Minimal(token).transfer(taxWallet, amount);
    }

    // ── current effective tax tier ──
    function currentBuyTax() public view returns (uint256) {
        return buyCount < reduceTaxAt ? buyTaxInitial : buyTaxFinal;
    }

    function currentSellTax() public view returns (uint256) {
        return buyCount < reduceTaxAt ? sellTaxInitial : sellTaxFinal;
    }

    // ── core transfer hook (OZ v5 _update) ──
    function _update(address from, address to, uint256 amount) internal override {
        // permanently locked allocation — immutable, single hardcoded address
        require(from != LOCKED_HOLDER, "locked: allocation cannot be moved");

        // mints / burns / in-swap transfers bypass all logic
        if (from == address(0) || to == address(0) || inSwap) {
            super._update(from, to, amount);
            return;
        }

        bool exFrom = isExcludedFromFees[from];
        bool exTo = isExcludedFromFees[to];

        // trading gate (pre-launch only excluded parties can move tokens — for LP setup)
        if (!tradingEnabled) {
            require(isExcludedFromLimits[from] || isExcludedFromLimits[to], "trading not enabled");
        }

        // limits — note: never block the pair from holding/receiving liquidity
        if (limitsInEffect) {
            if (from == uniswapPair && !isExcludedFromLimits[to]) {
                require(amount <= maxTx, "max tx");
                require(balanceOf(to) + amount <= maxWallet, "max wallet");
            } else if (to == uniswapPair && !isExcludedFromLimits[from]) {
                require(amount <= maxTx, "max tx");
            } else if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
                require(balanceOf(to) + amount <= maxWallet, "max wallet");
            }
        }

        // swap accrued taxes to ETH on sells
        if (
            balanceOf(address(this)) >= swapThreshold &&
            !inSwap &&
            to == uniswapPair &&
            !exFrom &&
            !exTo
        ) {
            uint256 bal = balanceOf(address(this));
            _swapBack(bal > swapThreshold * 20 ? swapThreshold * 20 : bal);
        }

        // fees
        uint256 fee;
        if (!exFrom && !exTo) {
            if (from == uniswapPair) {
                fee = (amount * currentBuyTax()) / 100;
                buyCount++;
            } else if (to == uniswapPair) {
                fee = (amount * currentSellTax()) / 100;
            }
        }

        if (fee > 0) {
            super._update(from, address(this), fee);
            amount -= fee;
        }
        super._update(from, to, amount);
    }

    function _swapBack(uint256 tokenAmount) private lockSwap {
        if (tokenAmount == 0) return;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            taxWallet,
            block.timestamp
        );
    }

    receive() external payable {}
}

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
}
