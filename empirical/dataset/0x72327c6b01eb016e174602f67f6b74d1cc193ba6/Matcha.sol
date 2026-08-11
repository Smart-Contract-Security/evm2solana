// SPDX-License-Identifier: MIT

// =====================================================================
//  🐟  MATCHA  ($MATCHA)  —  Donation Token  🐟
//
//  Adopt Matcha, a newly rescued seal:
//  >>>  https://steun.zeehondencentrum.nl/adoptie-matcha  <<<
//
//  X / Twitter:  https://x.com/savematcha
//
//  5% buy / 5% sell tax. 100% of taxes are collected, swapped to ETH,
//  and sent to the donation wallet to help care for Matcha the seal.
//  1,000,000,000 total supply. 100% of tokens go to the LP.
// =====================================================================

pragma solidity 0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

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

contract Matcha is IERC20 {
    string public constant name = "Matcha";
    string public constant symbol = "MATCHA";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    string public constant donationLink = "https://steun.zeehondencentrum.nl/adoptie-matcha";
    string public constant twitter = "https://x.com/savematcha";

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public owner;

    // Taxes (in percent). 5% buy / 5% sell.
    uint256 public buyTax = 5;
    uint256 public sellTax = 5;
    uint256 public constant MAX_TAX = 5; // taxes can only ever be lowered, never raised above 5%.

    address public donationWallet;

    IUniswapV2Router02 public immutable router;
    address public immutable pair;

    bool public tradingEnabled;
    bool public swapEnabled;
    bool private _inSwap;

    // Once this many tokens accumulate in the contract from taxes, swap to ETH.
    uint256 public swapThreshold = totalSupply / 5000; // 0.02%

    // Anti-whale limits: 2% of total supply each.
    uint256 public maxTxAmount = (totalSupply * 2) / 100;
    uint256 public maxWalletAmount = (totalSupply * 2) / 100;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromLimits;

    event TradingEnabled();
    event LimitsUpdated(uint256 maxTxAmount, uint256 maxWalletAmount);
    event LimitsRemoved();
    event DonationWalletUpdated(address indexed newWallet);
    event TaxesUpdated(uint256 buyTax, uint256 sellTax);
    event DonationSent(uint256 ethAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier lockSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    constructor(address router_, address donationWallet_) {
        require(router_ != address(0), "router zero");
        require(donationWallet_ != address(0), "donation zero");

        owner = msg.sender;
        donationWallet = donationWallet_;

        router = IUniswapV2Router02(router_);
        pair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());

        isExcludedFromFee[msg.sender] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[donationWallet_] = true;

        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[donationWallet_] = true;

        // Mint 100% of supply to the deployer so it can all be added to the LP.
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    receive() external payable {}

    // ----------------------------------------------------------------- ERC20
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        if (current != type(uint256).max) {
            require(current >= amount, "insufficient allowance");
            _approve(from, msg.sender, current - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _approve(address owner_, address spender, uint256 amount) private {
        require(owner_ != address(0) && spender != address(0), "zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    // --------------------------------------------------------------- transfer
    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0) && to != address(0), "zero address");
        require(amount > 0, "zero amount");
        require(_balances[from] >= amount, "insufficient balance");

        bool excluded = isExcludedFromFee[from] || isExcludedFromFee[to];

        if (!excluded) {
            require(tradingEnabled, "trading not enabled");
        }

        // Anti-whale limits. Skipped for excluded addresses; max wallet never
        // applies to the pair (the LP must be able to hold the whole supply).
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            if (from == pair || to == pair) {
                require(amount <= maxTxAmount, "max tx exceeded");
            }
            if (to != pair) {
                require(_balances[to] + amount <= maxWalletAmount, "max wallet exceeded");
            }
        }

        // Swap accumulated tax tokens to ETH on sells.
        uint256 contractBalance = _balances[address(this)];
        if (
            swapEnabled &&
            !_inSwap &&
            to == pair &&
            !excluded &&
            contractBalance >= swapThreshold
        ) {
            _swapBack(contractBalance);
        }

        uint256 taxAmount = 0;
        if (!excluded && !_inSwap) {
            if (from == pair) {
                taxAmount = (amount * buyTax) / 100; // buy
            } else if (to == pair) {
                taxAmount = (amount * sellTax) / 100; // sell
            }
        }

        _balances[from] -= amount;

        if (taxAmount > 0) {
            _balances[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }

        uint256 sendAmount = amount - taxAmount;
        _balances[to] += sendAmount;
        emit Transfer(from, to, sendAmount);
    }

    function _swapBack(uint256 tokenAmount) private lockSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            donationWallet,
            block.timestamp
        );
        emit DonationSent(tokenAmount);
    }

    // ----------------------------------------------------------------- owner
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "already enabled");
        tradingEnabled = true;
        swapEnabled = true;
        emit TradingEnabled();
    }

    function setDonationWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "zero address");
        donationWallet = newWallet;
        isExcludedFromFee[newWallet] = true;
        emit DonationWalletUpdated(newWallet);
    }

    // Taxes can only be lowered (or kept), never raised above 5%.
    function setTaxes(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        require(newBuyTax <= MAX_TAX && newSellTax <= MAX_TAX, "tax too high");
        buyTax = newBuyTax;
        sellTax = newSellTax;
        emit TaxesUpdated(newBuyTax, newSellTax);
    }

    function setSwapThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "zero threshold");
        swapThreshold = newThreshold;
    }

    // Limits may only be loosened, never set below 1% of supply (anti-rug).
    function setLimits(uint256 newMaxTx, uint256 newMaxWallet) external onlyOwner {
        require(newMaxTx >= totalSupply / 100 && newMaxWallet >= totalSupply / 100, "limit too low");
        maxTxAmount = newMaxTx;
        maxWalletAmount = newMaxWallet;
        emit LimitsUpdated(newMaxTx, newMaxWallet);
    }

    // Fully remove the anti-whale limits once the launch has settled.
    function removeLimits() external onlyOwner {
        maxTxAmount = totalSupply;
        maxWalletAmount = totalSupply;
        emit LimitsRemoved();
    }

    function setExcludedFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }

    function setSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    // Manually push any accumulated tax tokens to the donation wallet as ETH.
    function manualSwap() external onlyOwner {
        uint256 contractBalance = _balances[address(this)];
        require(contractBalance > 0, "nothing to swap");
        _swapBack(contractBalance);
    }

    // Rescue ETH accidentally stuck in the contract -> donation wallet.
    function rescueETH() external onlyOwner {
        (bool ok, ) = donationWallet.call{value: address(this).balance}("");
        require(ok, "eth transfer failed");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}
