// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        bool success = token.transfer(to, amount);
        require(success, "SafeERC20: transfer failed");
    }
}

contract ERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _update(from, to, amount);
    }

    function _update(address from, address to, uint256 amount) internal virtual {
        if (from == address(0)) {
            _totalSupply += amount;
        } else {
            uint256 fromBalance = _balances[from];
            require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
            _balances[from] = fromBalance - amount;
        }
        if (to == address(0)) {
            _totalSupply -= amount;
        } else {
            _balances[to] += amount;
        }
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        _update(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        _update(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
    }
}

contract ERC20Burnable is ERC20 {
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
    }
}

contract ERC20Permit is ERC20 {
    mapping(address => uint256) private _nonces;

    constructor(string memory name) ERC20(name, "") {}

    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                _nonces[owner]++,
                deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        address signer = recover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");
        _approve(owner, spender, value);
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        return address(uint160(uint256(keccak256(abi.encodePacked(prefixedHash, v, r, s)))));
    }

    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Pair {
    function skim(address to) external;
}

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function WETH() external view returns (address);
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

contract DunaldoToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;

    uint16 public constant BPS_DENOMINATOR = 10_000;

    struct TaxConfig {
        uint16 initialBuyTaxBps;
        uint16 finalBuyTaxBps;
        uint16 initialSellTaxBps;
        uint16 finalSellTaxBps;
        uint32 taxSwitchoverBlocks;
        uint16 maxTaxBps;
    }

    struct LimitConfig {
        bool limitsEnabled;
        uint256 maxWalletAmount;
    }

    struct ClogConfig {
        bool autoSwapEnabled;
        uint256 maxSwapAmount;
        uint32 minBlocksBetweenSwaps;
    }

    struct LaunchTokenConfig {
        string name;
        string symbol;
        uint8 decimals_;
        uint256 totalSupply;
        uint256 poolTokenAmount;
        address taxWallet;
        address uniswapV2Router;
        TaxConfig tax;
        LimitConfig limits;
        ClogConfig clog;
    }

    IUniswapV2Router02 public immutable UNISWAP_V2_ROUTER;
    uint8 private immutable TOKEN_DECIMALS;
    uint16 public immutable MAX_TAX_BPS;
    uint32 public immutable TAX_SWITCHOVER_BLOCKS;
    uint256 public immutable POOL_TOKEN_AMOUNT;

    address public uniswapV2Pair;
    address public taxWallet;

    uint16 public initialBuyTaxBps;
    uint16 public finalBuyTaxBps;
    uint16 public initialSellTaxBps;
    uint16 public finalSellTaxBps;

    bool public tradingActive;
    bool public launchTaxesFinalized;
    bool public limitsEnabled;
    bool public swapEnabled;
    bool public taxesAndLimitsRemoved;
    bool private swapping;

    uint32 public tradingActiveBlock;
    uint32 public minBlocksBetweenSwaps;
    uint32 public lastSwapBlock;

    uint256 public maxWalletAmount;
    uint256 public maxSwapAmount;

    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public automatedMarketMakerPairs;

    event PairCreated(address indexed pair);
    event TradingOpened(
        address indexed pair,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 liquidity,
        uint32 tradingActiveBlock
    );
    event LaunchTaxesFinalized(uint16 initialBuyTaxBps, uint16 initialSellTaxBps);
    event TaxesUpdated(
        uint16 initialBuyTaxBps,
        uint16 finalBuyTaxBps,
        uint16 initialSellTaxBps,
        uint16 finalSellTaxBps
    );
    event LimitsRemoved();
    event TaxesAndLimitsRemoved();
    event SwapEnabledSet(bool enabled);
    event TaxWalletUpdated(address indexed taxWallet);
    event TaxTokensSwapped(uint256 tokensSold);
    event RecoveredERC20(address indexed token, address indexed to, uint256 amount);

    error AlreadySet();
    error InvalidAmount();
    error InvalidRecipient();
    error InvalidTax();
    error LimitsAlreadyRemoved();
    error NotTaxWallet();
    error PairNotCreated();
    error SwapInProgress();
    error TaxesAndLimitsAlreadyRemoved();
    error TradingAlreadyActive();
    error TradingNotActive();
    error TradingNotOpen();
    error UnauthorizedTransferBeforeTrading();

    constructor(LaunchTokenConfig memory config)
        ERC20(config.name, config.symbol)
        ERC20Permit(config.name)
        Ownable()
    {
        TOKEN_DECIMALS = config.decimals_;
        POOL_TOKEN_AMOUNT = config.poolTokenAmount;
        taxWallet = config.taxWallet;
        UNISWAP_V2_ROUTER = IUniswapV2Router02(config.uniswapV2Router);

        initialBuyTaxBps = config.tax.initialBuyTaxBps;
        finalBuyTaxBps = config.tax.finalBuyTaxBps;
        initialSellTaxBps = config.tax.initialSellTaxBps;
        finalSellTaxBps = config.tax.finalSellTaxBps;
        MAX_TAX_BPS = config.tax.maxTaxBps;
        TAX_SWITCHOVER_BLOCKS = config.tax.taxSwitchoverBlocks;

        limitsEnabled = config.limits.limitsEnabled;
        maxWalletAmount = config.limits.maxWalletAmount;

        swapEnabled = config.clog.autoSwapEnabled;
        maxSwapAmount = config.clog.maxSwapAmount;
        minBlocksBetweenSwaps = config.clog.minBlocksBetweenSwaps;
        launchTaxesFinalized = config.tax.initialBuyTaxBps != 0 || config.tax.initialSellTaxBps != 0;

        _setFeeExcluded(msg.sender, true);
        _setFeeExcluded(address(this), true);
        _setFeeExcluded(config.taxWallet, true);
        _setFeeExcluded(config.uniswapV2Router, true);

        _setLimitExcluded(msg.sender, true);
        _setLimitExcluded(address(this), true);
        _setLimitExcluded(config.taxWallet, true);
        _setLimitExcluded(config.uniswapV2Router, true);
        _setLimitExcluded(address(0xdead), true);

        _mint(address(this), config.poolTokenAmount);
        uint256 retainedSupply = config.totalSupply - config.poolTokenAmount;
        if (retainedSupply != 0) {
            _mint(msg.sender, retainedSupply);
        }
    }

    function decimals() public view override returns (uint8) {
        return TOKEN_DECIMALS;
    }

    function createPair() external onlyOwner returns (address pair) {
        if (tradingActive) revert TradingAlreadyActive();

        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_ROUTER.factory());
        address weth = UNISWAP_V2_ROUTER.WETH();
        pair = factory.createPair(address(this), weth);

        uniswapV2Pair = pair;
        automatedMarketMakerPairs[pair] = true;
        _setLimitExcluded(pair, true);

        emit PairCreated(pair);
    }

    function openTrading(
        uint256 tokenAmount,
        uint256 amountTokenMin,
        uint256 amountEthMin,
        address lpRecipient
    ) external payable onlyOwner {
        address pair = uniswapV2Pair;
        if (pair == address(0)) revert PairNotCreated();
        if (tradingActive) revert TradingAlreadyActive();

        IUniswapV2Pair(pair).skim(taxWallet);
        _approve(address(this), address(UNISWAP_V2_ROUTER), type(uint256).max);

        (uint256 amountToken, uint256 amountEth, uint256 liquidity) = UNISWAP_V2_ROUTER.addLiquidityETH{
            value: msg.value
        }(
            address(this), tokenAmount, amountTokenMin, amountEthMin, lpRecipient, block.timestamp
        );

        tradingActive = true;
        tradingActiveBlock = uint32(block.number);

        emit TradingOpened(pair, amountToken, amountEth, liquidity, tradingActiveBlock);
    }

    function finalizeLaunchTaxes(uint16 newInitialBuyTaxBps, uint16 newInitialSellTaxBps)
        external
        onlyOwner
    {
        if (!tradingActive) revert TradingNotActive();
        if (launchTaxesFinalized) revert AlreadySet();
        if (initialBuyTaxBps != 0 || initialSellTaxBps != 0) revert AlreadySet();
        if (newInitialBuyTaxBps > MAX_TAX_BPS || newInitialSellTaxBps > MAX_TAX_BPS) {
            revert InvalidTax();
        }

        initialBuyTaxBps = newInitialBuyTaxBps;
        initialSellTaxBps = newInitialSellTaxBps;
        launchTaxesFinalized = true;

        emit LaunchTaxesFinalized(newInitialBuyTaxBps, newInitialSellTaxBps);
    }

    function setTaxes(
        uint16 newInitialBuyTaxBps,
        uint16 newFinalBuyTaxBps,
        uint16 newInitialSellTaxBps,
        uint16 newFinalSellTaxBps
    ) external onlyTaxWallet {
        if (taxesAndLimitsRemoved) revert TaxesAndLimitsAlreadyRemoved();
        if (!launchTaxesFinalized) revert TradingNotOpen();
        if (
            newInitialBuyTaxBps > MAX_TAX_BPS || newFinalBuyTaxBps > MAX_TAX_BPS
                || newInitialSellTaxBps > MAX_TAX_BPS || newFinalSellTaxBps > MAX_TAX_BPS
        ) {
            revert InvalidTax();
        }

        initialBuyTaxBps = newInitialBuyTaxBps;
        finalBuyTaxBps = newFinalBuyTaxBps;
        initialSellTaxBps = newInitialSellTaxBps;
        finalSellTaxBps = newFinalSellTaxBps;

        emit TaxesUpdated(
            newInitialBuyTaxBps, newFinalBuyTaxBps, newInitialSellTaxBps, newFinalSellTaxBps
        );
    }

    function setTaxWallet(address newTaxWallet) external onlyTaxWallet {
        if (newTaxWallet == address(0)) revert InvalidRecipient();
        address oldTaxWallet = taxWallet;
        taxWallet = newTaxWallet;
        _clearRoleExclusionIfUnused(oldTaxWallet);
        _setFeeExcluded(taxWallet, true);
        _setLimitExcluded(taxWallet, true);
        emit TaxWalletUpdated(taxWallet);
    }

    function removeLimits() external onlyTaxWallet {
        if (!limitsEnabled) revert LimitsAlreadyRemoved();
        limitsEnabled = false;
        emit LimitsRemoved();
    }

    function removeTaxesAndLimits() external onlyTaxWallet {
        taxesAndLimitsRemoved = true;
        limitsEnabled = false;
        swapEnabled = false;
        initialBuyTaxBps = 0;
        finalBuyTaxBps = 0;
        initialSellTaxBps = 0;
        finalSellTaxBps = 0;
        emit TaxesAndLimitsRemoved();
    }

    function setSwapEnabled(bool enabled) external onlyTaxWallet {
        if (taxesAndLimitsRemoved) revert TaxesAndLimitsAlreadyRemoved();
        swapEnabled = enabled;
        emit SwapEnabledSet(enabled);
    }

    function manualSwap(uint256 tokenAmount, uint256 minOut) external onlyTaxWallet {
        _swapTaxTokens(tokenAmount, minOut);
    }

    function recoverERC20(address token, uint256 amount, address to) external onlyTaxWallet {
        if (token == address(0) || to == address(0) || amount == 0) revert InvalidAmount();
        if (token == address(this) && to != taxWallet) revert InvalidRecipient();

        IERC20(token).safeTransfer(to, amount);
        emit RecoveredERC20(token, to, amount);
    }

    modifier onlyTaxWallet() {
        _checkTaxWallet();
        _;
    }

    function _checkTaxWallet() private view {
        if (msg.sender != taxWallet) revert NotTaxWallet();
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        if (swapping) {
            super._update(from, to, amount);
            return;
        }

        if (!tradingActive && !isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            revert UnauthorizedTransferBeforeTrading();
        }

        if (taxesAndLimitsRemoved) {
            super._update(from, to, amount);
            return;
        }

        bool isBuy = automatedMarketMakerPairs[from];
        bool isSell = automatedMarketMakerPairs[to];
        bool takeFee = tradingActive && !isExcludedFromFees[from] && !isExcludedFromFees[to];
        uint256 feeAmount = takeFee ? _feeAmount(amount, isBuy, isSell) : 0;
        uint256 transferAmount = amount - feeAmount;

        _enforceLimits(from, to, amount, transferAmount, isBuy, isSell);

        if (_shouldAutoSwap(from, isSell)) {
            _swapTaxTokens(_min(_min(balanceOf(address(this)), maxSwapAmount), amount), 0);
        }

        if (feeAmount > 0) {
            super._update(from, address(this), feeAmount);
        }
        super._update(from, to, transferAmount);
    }

    function _feeAmount(uint256 amount, bool isBuy, bool isSell) private view returns (uint256) {
        uint16 taxBps;
        if (isBuy) {
            taxBps = _currentBuyTaxBps();
        } else if (isSell) {
            taxBps = _currentSellTaxBps();
        }
        return taxBps == 0 ? 0 : (amount * taxBps) / BPS_DENOMINATOR;
    }

    function _currentBuyTaxBps() private view returns (uint16) {
        return _initialTaxPeriodActive() ? initialBuyTaxBps : finalBuyTaxBps;
    }

    function _currentSellTaxBps() private view returns (uint16) {
        return _initialTaxPeriodActive() ? initialSellTaxBps : finalSellTaxBps;
    }

    function _initialTaxPeriodActive() private view returns (bool) {
        return tradingActive && block.number < uint256(tradingActiveBlock) + TAX_SWITCHOVER_BLOCKS;
    }

    function _enforceLimits(
        address from,
        address to,
        uint256,
        uint256 transferAmount,
        bool isBuy,
        bool isSell
    ) private view {
        if (!limitsEnabled) return;

        if (isBuy && !isExcludedFromLimits[to]) {
            if (maxWalletAmount != 0 && balanceOf(to) + transferAmount > maxWalletAmount) {
                revert InvalidAmount();
            }
            return;
        }

        if (isSell && !isExcludedFromLimits[from]) {
            return;
        }

        if (!isBuy && !isSell && !isExcludedFromLimits[to]) {
            if (maxWalletAmount != 0 && balanceOf(to) + transferAmount > maxWalletAmount) {
                revert InvalidAmount();
            }
        }
    }

    function _shouldAutoSwap(address from, bool isSell) private view returns (bool) {
        if (!isSell || from == address(this) || isExcludedFromFees[from]) return false;
        if (!swapEnabled || maxSwapAmount == 0) return false;
        if (balanceOf(address(this)) / 2 < maxSwapAmount) return false;
        return block.number >= uint256(lastSwapBlock) + minBlocksBetweenSwaps;
    }

    function _swapTaxTokens(uint256 tokenAmount, uint256 minOut) private {
        if (tokenAmount == 0 || tokenAmount > balanceOf(address(this))) revert InvalidAmount();
        if (swapping) revert SwapInProgress();

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = UNISWAP_V2_ROUTER.WETH();

        swapping = true;
        UNISWAP_V2_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, minOut, path, taxWallet, block.timestamp
        );
        swapping = false;
        lastSwapBlock = uint32(block.number);
        emit TaxTokensSwapped(tokenAmount);
    }

    function _setFeeExcluded(address account, bool excluded) private {
        isExcludedFromFees[account] = excluded;
    }

    function _setLimitExcluded(address account, bool excluded) private {
        isExcludedFromLimits[account] = excluded;
    }

    function _clearRoleExclusionIfUnused(address account) private {
        if (
            account == owner() || account == address(this) || account == taxWallet
                || account == address(UNISWAP_V2_ROUTER) || account == uniswapV2Pair
        ) {
            return;
        }
        _setFeeExcluded(account, false);
        _setLimitExcluded(account, false);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}