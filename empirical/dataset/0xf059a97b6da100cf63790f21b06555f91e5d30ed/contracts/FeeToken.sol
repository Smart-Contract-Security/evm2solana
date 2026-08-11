// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Parameterized ERC-20 derived from the publicly verified mainnet token at
// https://etherscan.io/token/0x1121AcC14c63f3C872BFcA497d10926A6098AAc5#code
// The original source hard-codes a name/symbol/marketing wallet and a 10%/30%
// buy/sell fee schedule. This version accepts those values through the
// constructor so the same bytecode can be reused for new launches.
//
// Behavior preserved from the source, verbatim unless noted:
//   - Uniswap V2 pair creation at deploy time and automated-market-maker flag.
//   - Buy/sell fees split into marketing/liquidity/dev buckets (capped at 50%
//     buy / 99% sell in update functions).
//   - Max transaction, max wallet, per-block transfer delay, trading toggle.
//   - `_blacklist` mapping and `blacklistAccounts` admin call are kept to stay
//     faithful to the verified source. Owners must disclose this to users.
//   - `swapBack` converts collected fee tokens to ETH via the router and sends
//     the proceeds to the configured marketing and dev wallets.
//
// Divergences from the source:
//   - Name, symbol, router, marketing/dev wallets, fees, max tx/wallet percents,
//     and total supply are constructor parameters.
//   - Solidity upgraded only in pragma compatibility; no SafeMath removal.

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
        );
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        _beforeTokenTransfer(account, address(0), amount);
        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/// @title FeeToken
/// @notice Parameterized ERC-20 with Uniswap V2 pair, buy/sell taxes, max
/// wallet/max tx limits, trading toggle, and optional blacklist (kept from
/// the source contract being cloned — document to users).
contract FeeToken is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool private swapping;

    address public marketingWallet;
    address public devWallet;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    mapping(address => uint256) private _holderLastTransferTimestamp;
    mapping(address => bool) private _blacklist;
    bool public transferDelayEnabled = true;

    uint256 public buyTotalFees;
    uint256 public buyMarketingFee;
    uint256 public buyLiquidityFee;
    uint256 public buyDevFee;

    uint256 public sellTotalFees;
    uint256 public sellMarketingFee;
    uint256 public sellLiquidityFee;
    uint256 public sellDevFee;

    uint256 public tokensForMarketing;
    uint256 public tokensForLiquidity;
    uint256 public tokensForDev;

    // Cumulative ETH (wei) forwarded by swapBack, exposed so off-chain tools
    // can surface "taxes collected" without relying on event scraping. Only
    // tracks tokens that were actually converted via swapBack; tokens sitting
    // in the contract pre-swap are visible via balanceOf(address(this)).
    uint256 public totalEthToMarketing;
    uint256 public totalEthToDev;

    uint256 launchedAt;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;
    mapping(address => bool) public automatedMarketMakerPairs;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event marketingWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event devWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);

    struct DeployConfig {
        string name;
        string symbol;
        uint256 totalSupply;
        address router;
        address marketingWallet;
        address devWallet;
        uint256 buyFeePercent;
        uint256 sellFeePercent;
        uint256 maxWalletPercent;
        uint256 maxTxPercent;
    }

    /// @param cfg packed deploy config (see DeployConfig).
    /// totalSupply is expressed in whole tokens (multiplied by 1e18 in-contract).
    /// buy/sell fee percents are capped at 50%/99% to match the source's admin
    /// limits; the original token launched with 10% buy / 30% sell.
    /// maxWalletPercent / maxTxPercent are expressed in percent (e.g. 2 = 2%).
    constructor(DeployConfig memory cfg) ERC20(cfg.name, cfg.symbol) {
        require(cfg.router != address(0), "router required");
        require(cfg.marketingWallet != address(0), "marketing wallet required");
        require(cfg.devWallet != address(0), "dev wallet required");
        require(cfg.buyFeePercent <= 50, "buy fee too high");
        require(cfg.sellFeePercent <= 99, "sell fee too high");
        require(cfg.maxWalletPercent >= 1 && cfg.maxWalletPercent <= 100, "maxWallet%");
        require(cfg.maxTxPercent >= 1 && cfg.maxTxPercent <= 100, "maxTx%");
        require(cfg.totalSupply > 0, "supply required");

        IUniswapV2Router02 _router = IUniswapV2Router02(cfg.router);

        uint256 supplyWei = cfg.totalSupply * 1e18;

        marketingWallet = cfg.marketingWallet;
        devWallet = cfg.devWallet;

        uniswapV2Router = _router;
        excludeFromMaxTransaction(address(_router), true);

        address pair = IUniswapV2Factory(_router.factory()).createPair(address(this), _router.WETH());
        uniswapV2Pair = pair;
        excludeFromMaxTransaction(pair, true);
        _setAutomatedMarketMakerPair(pair, true);

        // All fees go to marketing by default; owner may re-split via
        // updateBuyFees / updateSellFees.
        buyMarketingFee = cfg.buyFeePercent;
        buyLiquidityFee = 0;
        buyDevFee = 0;
        buyTotalFees = buyMarketingFee + buyLiquidityFee + buyDevFee;

        sellMarketingFee = cfg.sellFeePercent;
        sellLiquidityFee = 0;
        sellDevFee = 0;
        sellTotalFees = sellMarketingFee + sellLiquidityFee + sellDevFee;

        maxTransactionAmount = (supplyWei * cfg.maxTxPercent) / 100;
        maxWallet = (supplyWei * cfg.maxWalletPercent) / 100;
        swapTokensAtAmount = (supplyWei * 5) / 10000; // 0.05%

        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(cfg.devWallet, true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);
        // Dev wallet must be able to move its full balance (e.g. a 9%-of-supply
        // dead burn). Exempting it from max-tx/max-wallet mirrors the
        // owner/contract exemptions and avoids requiring a follow-up
        // excludeFromMaxTransaction tx before every large dev move.
        excludeFromMaxTransaction(cfg.devWallet, true);

        _mint(msg.sender, supplyWei);
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
        launchedAt = block.number;
    }

    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    function disableTransferDelay() external onlyOwner returns (bool) {
        transferDelayEnabled = false;
        return true;
    }

    function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
        require(newAmount >= (totalSupply() * 1) / 100000, "Swap amount cannot be lower than 0.001% total supply.");
        require(newAmount <= (totalSupply() * 5) / 1000, "Swap amount cannot be higher than 0.5% total supply.");
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 5) / 1000) / 1e18, "Cannot set maxTransactionAmount lower than 0.5%");
        maxTransactionAmount = newNum * (10 ** 18);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 15) / 1000) / 1e18, "Cannot set maxWallet lower than 1.5%");
        maxWallet = newNum * (10 ** 18);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx) public onlyOwner {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateBuyFees(uint256 _marketingFee, uint256 _liquidityFee, uint256 _devFee) external onlyOwner {
        buyMarketingFee = _marketingFee;
        buyLiquidityFee = _liquidityFee;
        buyDevFee = _devFee;
        buyTotalFees = buyMarketingFee + buyLiquidityFee + buyDevFee;
        require(buyTotalFees <= 50, "Must keep fees at 50% or less");
    }

    function updateSellFees(uint256 _marketingFee, uint256 _liquidityFee, uint256 _devFee) external onlyOwner {
        sellMarketingFee = _marketingFee;
        sellLiquidityFee = _liquidityFee;
        sellDevFee = _devFee;
        sellTotalFees = sellMarketingFee + sellLiquidityFee + sellDevFee;
        require(sellTotalFees <= 99, "Must keep fees at 99% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    /// @notice Inherited from the source contract. Blacklisted addresses cannot
    /// send or receive the token. Disclose clearly to any purchasers.
    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }

    function blacklistAccounts(address[] memory accounts, bool blacklisted) public onlyOwner {
        require(accounts.length > 0, "Accounts list cannot be empty.");
        for (uint256 i = 0; i < accounts.length; i++) {
            _blacklist[accounts[i]] = blacklisted;
        }
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateMarketingWallet(address newMarketingWallet) external onlyOwner {
        require(newMarketingWallet != address(0), "marketing wallet required");
        emit marketingWalletUpdated(newMarketingWallet, marketingWallet);
        marketingWallet = newMarketingWallet;
    }

    function updateDevWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "dev wallet required");
        emit devWalletUpdated(newWallet, devWallet);
        devWallet = newWallet;
        // Ensure the new dev wallet inherits the same limit/fee exemptions as
        // the original so large dev moves (e.g. burning a percent of supply)
        // don't trip max-tx / max-wallet. Safe to re-set; idempotent.
        _isExcludedFromFees[newWallet] = true;
        emit ExcludeFromFees(newWallet, true);
        _isExcludedMaxTransactionAmount[newWallet] = true;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_blacklist[to] && !_blacklist[from], "You have been blacklisted from transfering tokens");
        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead) && !swapping) {
                if (!tradingActive) {
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
                }

                if (transferDelayEnabled) {
                    if (to != owner() && to != address(uniswapV2Router) && to != address(uniswapV2Pair)) {
                        require(
                            _holderLastTransferTimestamp[tx.origin] < block.number,
                            "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                        );
                        _holderLastTransferTimestamp[tx.origin] = block.number;
                    }
                }

                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                } else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount <= maxTransactionAmount, "Sell transfer amount exceeds the maxTransactionAmount.");
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = !swapping;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        if (takeFee) {
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = amount.mul(sellTotalFees).div(100);
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForDev += (fees * sellDevFee) / sellTotalFees;
                tokensForMarketing += (fees * sellMarketingFee) / sellTotalFees;
            } else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForDev += (fees * buyDevFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity + tokensForMarketing + tokensForDev;
        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) / totalTokensToSwap / 2;
        uint256 amountToSwapForETH = contractBalance.sub(liquidityTokens);

        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(amountToSwapForETH);
        uint256 ethBalance = address(this).balance.sub(initialETHBalance);

        uint256 ethForDev = ethBalance.mul(tokensForDev).div(totalTokensToSwap);

        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForDev = 0;

        totalEthToDev += ethForDev;
        uint256 ethForMarketing = address(this).balance;
        totalEthToMarketing += ethForMarketing;

        (success, ) = address(devWallet).call{value: ethForDev}("");
        (success, ) = address(marketingWallet).call{value: ethForMarketing}("");
    }

    /// @notice Owner-triggered swapBack. Converts any collected fee tokens
    /// sitting in the contract to ETH and forwards proceeds to the
    /// marketing/dev wallets. Reverts if there is nothing to swap or swaps
    /// are currently disabled.
    function forceSwapBack() external onlyOwner {
        require(swapEnabled, "swaps disabled");
        uint256 contractBalance = balanceOf(address(this));
        require(contractBalance > 0, "no tokens to swap");
        require(
            tokensForLiquidity + tokensForMarketing + tokensForDev > 0,
            "no fees accrued"
        );
        swapping = true;
        swapBack();
        swapping = false;
    }
}
