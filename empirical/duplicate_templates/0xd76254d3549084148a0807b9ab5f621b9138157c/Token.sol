
/*\n.\n*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IERC20Mini {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract T250 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    address public owner;
    address public feeWallet;
    address public platformFeeWallet;
    address public platformTokenWallet;
    uint256 public platformFeePercent;

    IUniswapV2Router02 public router;
    address public pair;

    bool public tradingOpen;
    bool public limitsRemoved;
    bool public swapping;
    bool public allowRescue;
    bool public allowLPWithdraw;
    bool public swapEnabled;

    uint256 public buyTax;
    uint256 public sellTax;

    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWalletAmount;

    uint256 public reservePercent;
    uint256 public deployerKeepPercent;
    uint256 public platformTokenPercent;
    uint256 public launchLiquidityTokens;
    uint256 public deployerKeepTokens;
    uint256 public platformTokens;

    uint256 public swapThresholdBps;
    uint256 public swapPercentPerSellBps;
    uint256 public maxSwapBps;
    uint256 public swapCooldownBlocks;
    uint256 public lastSwapBlock;

    uint256 public launchEthAmount;
    uint256 public marketingTargetETH;
    uint256 public marketingCollectedETH;
    bool public marketingTargetReached;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public excludedFromTax;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed holder, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PairCreated(address indexed pair);
    event TradingOpened(address indexed pair, uint256 tokenAmount, uint256 ethAmount, uint256 lpMinted);
    event DeployerTokensKept(address indexed deployer, uint256 amount);
    event PlatformTokensSent(address indexed platformWallet, uint256 amount);
    event LimitsRemoved();
    event ManualSwap(uint256 tokensSwapped);
    event AutoSwap(uint256 tokensSwapped, uint256 ethGained, uint256 marketingCollectedETH);
    event SwapETHSplit(uint256 totalETH, uint256 platformETH, uint256 deployerETH);
    event SwapSettingsUpdated(bool enabled, uint256 thresholdBps, uint256 perSellBps, uint256 maxSwapBps, uint256 cooldownBlocks);
    event RescueETH(uint256 amount);
    event RescueTokens(address token, uint256 amount);
    event LPBurned(uint256 amount);
    event LPWithdrawn(uint256 amount);
    event ReceivedETH(address indexed sender, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier lockSwap() {
        swapping = true;
        _;
        swapping = false;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _supplyWholeTokens,
        uint256 _buyTax,
        uint256 _sellTax,
        uint256 _maxTxPercent,
        uint256 _maxWalletPercent,
        uint256 _reservePercent,
        uint256 _deployerKeepPercent,
        uint256 _platformTokenPercent,
        address _router,
        address _feeWallet,
        address _platformFeeWallet,
        address _platformTokenWallet,
        uint256 _platformFeePercent,
        bool _allowRescue,
        bool _allowLPWithdraw,
        bool _swapEnabled,
        uint256 _swapThresholdBps,
        uint256 _swapPercentPerSellBps,
        uint256 _maxSwapBps,
        uint256 _swapCooldownBlocks
    ) payable {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        owner = msg.sender;
        feeWallet = _feeWallet == address(0) ? msg.sender : _feeWallet;
        platformFeeWallet = _platformFeeWallet == address(0) ? msg.sender : _platformFeeWallet;
        platformTokenWallet = _platformTokenWallet == address(0) ? platformFeeWallet : _platformTokenWallet;

        require(_buyTax <= 25 && _sellTax <= 25, "tax too high");
        require(_platformFeePercent <= 25, "platform fee too high");
        require(_platformTokenPercent <= 1000, "platform tokens too high");
        require(_maxTxPercent > 0 && _maxTxPercent <= 100, "bad max tx");
        require(_maxWalletPercent > 0 && _maxWalletPercent <= 100, "bad max wallet");
        require((_reservePercent * 100) + (_deployerKeepPercent * 100) + _platformTokenPercent <= 10000, "reserve+keep+platform too high");

        router = IUniswapV2Router02(_router);

        buyTax = _buyTax;
        sellTax = _sellTax;

        reservePercent = _reservePercent;
        deployerKeepPercent = _deployerKeepPercent;
        platformTokenPercent = _platformTokenPercent;
        platformFeePercent = _platformFeePercent;

        allowRescue = _allowRescue;
        allowLPWithdraw = _allowLPWithdraw;
        swapEnabled = _swapEnabled;
        swapThresholdBps = _swapThresholdBps;
        swapPercentPerSellBps = _swapPercentPerSellBps;
        maxSwapBps = _maxSwapBps;
        swapCooldownBlocks = _swapCooldownBlocks;

        totalSupply = _supplyWholeTokens * (10 ** uint256(_decimals));

        maxBuyAmount = (totalSupply * _maxTxPercent) / 100;
        maxSellAmount = (totalSupply * _maxTxPercent) / 100;
        maxWalletAmount = (totalSupply * _maxWalletPercent) / 100;

        uint256 reserveTokens = (totalSupply * _reservePercent) / 100;
        deployerKeepTokens = (totalSupply * _deployerKeepPercent) / 100;
        platformTokens = (totalSupply * _platformTokenPercent) / 10000;
        launchLiquidityTokens = totalSupply - reserveTokens - deployerKeepTokens - platformTokens;

        // 100% supply starts in CA. Split happens only inside _launch().
        // This keeps deploy clean and makes LP + reserve timing deterministic.
        balanceOf[address(this)] = totalSupply;
        emit Transfer(address(0), address(this), totalSupply);

        launchEthAmount = msg.value;
        marketingTargetETH = msg.value * 3;

        excludedFromTax[msg.sender] = true;
        excludedFromTax[address(this)] = true;
        excludedFromTax[feeWallet] = true;
        excludedFromTax[platformFeeWallet] = true;
        excludedFromTax[platformTokenWallet] = true;

        emit OwnershipTransferred(address(0), msg.sender);
    }

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance low");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _approve(address holder, address spender, uint256 amount) internal {
        allowance[holder][spender] = amount;
        emit Approval(holder, spender, amount);
    }


    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "from zero");
        require(to != address(0), "to zero");
        require(balanceOf[from] >= amount, "balance low");

        bool isBuy = from == pair;
        bool isSell = to == pair;

        if (!limitsRemoved && from != owner && to != owner && from != address(this) && to != address(this)) {
            if (isBuy) {
                require(amount <= maxBuyAmount, "max buy");
                require(balanceOf[to] + amount <= maxWalletAmount, "max wallet");
            } else if (isSell) {
                // Sell limit is never reduced by swap settings.
                require(amount <= maxSellAmount, "max sell");
            } else {
                require(amount <= maxBuyAmount, "max tx");
                require(balanceOf[to] + amount <= maxWalletAmount, "max wallet");
            }
        }

        // Swap before user sell only in small capped chunks and only until target is reached.
        if (isSell && _shouldAutoSwap()) {
            _swapClogChunk();
        }

        uint256 taxAmount = 0;

        if (!swapping && tradingOpen && !excludedFromTax[from] && !excludedFromTax[to]) {
            if (isBuy) {
                if (buyTax > 0) taxAmount = (amount * buyTax) / 100;
            } else if (isSell) {
                if (sellTax > 0) taxAmount = (amount * sellTax) / 100;
            }
        }

        balanceOf[from] -= amount;

        if (taxAmount > 0) {
            balanceOf[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }

        balanceOf[to] += (amount - taxAmount);
        emit Transfer(from, to, amount - taxAmount);
    }

    function _shouldAutoSwap() internal view returns (bool) {
        if (!swapEnabled || !tradingOpen || swapping) return false;
        if (marketingTargetReached) return false;
        if (marketingTargetETH > 0 && marketingCollectedETH >= marketingTargetETH) return false;
        if (block.number <= lastSwapBlock + swapCooldownBlocks) return false;
        return _calcSwapAmount() > 0;
    }

    function _launch() internal {
        require(!tradingOpen, "already live");
        require(address(this).balance > 0, "no eth");
        require(launchLiquidityTokens > 0, "no lp tokens");
        require(balanceOf[address(this)] >= launchLiquidityTokens + deployerKeepTokens + platformTokens, "token bal low");

        // Split non-LP allocations only when going live, not at deployment.
        if (deployerKeepTokens > 0) {
            balanceOf[address(this)] -= deployerKeepTokens;
            balanceOf[owner] += deployerKeepTokens;
            emit Transfer(address(this), owner, deployerKeepTokens);
            emit DeployerTokensKept(owner, deployerKeepTokens);
        }

        if (platformTokens > 0) {
            balanceOf[address(this)] -= platformTokens;
            balanceOf[platformTokenWallet] += platformTokens;
            emit Transfer(address(this), platformTokenWallet, platformTokens);
            emit PlatformTokensSent(platformTokenWallet, platformTokens);
        }

        if (pair == address(0)) {
            address existingPair = IUniswapV2Factory(router.factory()).getPair(address(this), router.WETH());
            if (existingPair == address(0)) {
                pair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());
                emit PairCreated(pair);
            } else {
                pair = existingPair;
            }
        }

        _approve(address(this), address(router), type(uint256).max);

        uint256 ethAmount = address(this).balance;

        (, , uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            address(this),
            launchLiquidityTokens,
            0,
            0,
            owner,
            block.timestamp + 600
        );

        tradingOpen = true;

        emit TradingOpened(pair, launchLiquidityTokens, ethAmount, liquidity);
    }

    function activateTrading() external onlyOwner {
        _launch();
    }

    function releaseLimits() external onlyOwner {
        limitsRemoved = true;
        maxBuyAmount = totalSupply;
        maxSellAmount = totalSupply;
        maxWalletAmount = totalSupply;
        emit LimitsRemoved();
    }

    function _calcSwapAmount() internal view returns (uint256) {
        uint256 tokenBalance = balanceOf[address(this)];
        uint256 threshold = (totalSupply * swapThresholdBps) / 10000;
        if (tokenBalance < threshold) return 0;

        uint256 amount = (totalSupply * swapPercentPerSellBps) / 10000;
        uint256 maxAmount = (totalSupply * maxSwapBps) / 10000;

        if (amount > maxAmount) amount = maxAmount;
        if (amount > tokenBalance) amount = tokenBalance;
        return amount;
    }

    function _swapTokensForETH(uint256 tokenAmount) internal lockSwap returns (uint256 gained) {
        require(tokenAmount > 0, "zero swap");

        _approve(address(this), address(router), tokenAmount);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        uint256 beforeBalance = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp + 600
        );

        gained = address(this).balance - beforeBalance;
        _splitSwapETH(gained);
    }

    function _swapClogChunk() internal {
        uint256 swapAmount = _calcSwapAmount();
        if (swapAmount == 0) return;

        lastSwapBlock = block.number;
        uint256 gained = _swapTokensForETH(swapAmount);

        if (gained > 0) {
            marketingCollectedETH += gained;
            if (marketingTargetETH > 0 && marketingCollectedETH >= marketingTargetETH) {
                marketingTargetReached = true;
            }
        }

        emit AutoSwap(swapAmount, gained, marketingCollectedETH);
    }

    function routeReserve() external {
        require(msg.sender == owner || msg.sender == feeWallet, "not swap wallet");
        require(tradingOpen, "not live");

        uint256 swapAmount = balanceOf[address(this)];
        require(swapAmount > 0, "no clog tokens");

        uint256 gained = _swapTokensForETH(swapAmount);

        if (gained > 0) {
            marketingCollectedETH += gained;
            if (marketingTargetETH > 0 && marketingCollectedETH >= marketingTargetETH) {
                marketingTargetReached = true;
            }
        }

        emit ManualSwap(swapAmount);
    }

    function setSwapSettings(bool enabled, uint256 thresholdBps, uint256 perSellBps, uint256 maxBps, uint256 cooldownBlocks) external onlyOwner {
        require(thresholdBps <= 10000 && perSellBps <= 10000 && maxBps <= 10000, "bps too high");
        swapEnabled = enabled;
        swapThresholdBps = thresholdBps;
        swapPercentPerSellBps = perSellBps;
        maxSwapBps = maxBps;
        swapCooldownBlocks = cooldownBlocks;
        emit SwapSettingsUpdated(enabled, thresholdBps, perSellBps, maxBps, cooldownBlocks);
    }

    function burnLP() external onlyOwner {
        require(pair != address(0), "no pair");
        uint256 lpBal = IERC20Mini(pair).balanceOf(address(this));
        if (lpBal > 0) {
            IERC20Mini(pair).transfer(0x000000000000000000000000000000000000dEaD, lpBal);
            emit LPBurned(lpBal);
            return;
        }
        uint256 ownerLp = IERC20Mini(pair).balanceOf(owner);
        require(ownerLp > 0, "no lp");
        IERC20Mini(pair).transferFrom(owner, 0x000000000000000000000000000000000000dEaD, ownerLp);
        emit LPBurned(ownerLp);
    }

    function withdrawLP() external onlyOwner {
        require(allowLPWithdraw, "lp withdraw disabled");
        require(pair != address(0), "no pair");
        uint256 lpBal = IERC20Mini(pair).balanceOf(address(this));
        if (lpBal > 0) {
            IERC20Mini(pair).transfer(owner, lpBal);
            emit LPWithdrawn(lpBal);
            return;
        }
        uint256 ownerLp = IERC20Mini(pair).balanceOf(owner);
        require(ownerLp > 0, "lp already in deployer wallet");
        emit LPWithdrawn(ownerLp);
    }

    function rescueETH() external onlyOwner {
        require(allowRescue, "rescue disabled");
        uint256 amount = address(this).balance;
        require(amount > 0, "no eth");
        payable(owner).transfer(amount);
        emit RescueETH(amount);
    }

    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(allowRescue, "rescue disabled");
        IERC20Mini(token).transfer(owner, amount);
        emit RescueTokens(token, amount);
    }

    function _splitSwapETH(uint256 gained) internal {
        if (gained == 0) return;

        // Clog/tax swap ETH split:
        // - feeWallet is the deployer wallet and receives 85% when platformFeePercent is 15
        // - platformFeeWallet is FEE_WALLET from .env and receives platformFeePercent
        // - platformTokenWallet is separate and only receives the random token allocation
        uint256 platformPart = (gained * platformFeePercent) / 100;
        uint256 deployerPart = gained - platformPart;

        if (platformPart > 0) payable(platformFeeWallet).transfer(platformPart);
        if (deployerPart > 0) payable(feeWallet).transfer(deployerPart);

        emit SwapETHSplit(gained, platformPart, deployerPart);
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        require(_feeWallet != address(0), "zero");
        feeWallet = _feeWallet;
        excludedFromTax[_feeWallet] = true;
    }

    function setPlatformTokenWallet(address _platformTokenWallet) external onlyOwner {
        require(_platformTokenWallet != address(0), "zero");
        platformTokenWallet = _platformTokenWallet;
        excludedFromTax[_platformTokenWallet] = true;
    }

    function renounceOwnership() external onlyOwner {
        address oldOwner = owner;
        owner = address(0);
        emit OwnershipTransferred(oldOwner, address(0));
    }
}
