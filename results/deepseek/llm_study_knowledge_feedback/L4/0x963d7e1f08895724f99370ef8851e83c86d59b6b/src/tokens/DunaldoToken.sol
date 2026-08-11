// SPDX-License-Identifier: MIT

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract DunaldoToken is Ownable {
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

    address public immutable UNISWAP_V2_ROUTER;
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

    // ERC20 state
    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _nonces;

    bytes32 private constant _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private immutable _DOMAIN_SEPARATOR;

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
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Deploys a configured Uniswap v2 launch token.
     * @param config Token metadata, launch allocation, authorities, tax, limits, and clog settings.
     */
    constructor(LaunchTokenConfig memory config) Ownable(tx.accounts.dataAccount.key) {
        _name = config.name;
        _symbol = config.symbol;
        TOKEN_DECIMALS = config.decimals_;
        POOL_TOKEN_AMOUNT = config.poolTokenAmount;
        taxWallet = config.taxWallet;
        UNISWAP_V2_ROUTER = config.uniswapV2Router;

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

        _DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(_name)),
            keccak256(bytes("1")),
            uint256(0),
            address(this)
        ));

        address owner = tx.accounts.dataAccount.key;
        _transferOwnership(owner);

        _setFeeExcluded(owner, true);
        _setFeeExcluded(address(this), true);
        _setFeeExcluded(config.taxWallet, true);
        _setFeeExcluded(config.uniswapV2Router, true);

        _setLimitExcluded(owner, true);
        _setLimitExcluded(address(this), true);
        _setLimitExcluded(config.taxWallet, true);
        _setLimitExcluded(config.uniswapV2Router, true);
        _setLimitExcluded(address(0xdead), true);

        _mint(address(this), config.poolTokenAmount);
        uint256 retainedSupply = config.totalSupply - config.poolTokenAmount;
        if (retainedSupply != 0) {
            _mint(owner, retainedSupply);
        }
    }

    // ERC20 standard functions
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return TOKEN_DECIMALS;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(tx.accounts.dataAccount.key, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(tx.accounts.dataAccount.key, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _spendAllowance(from, tx.accounts.dataAccount.key, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        address sender = tx.accounts.dataAccount.key;
        _approve(sender, spender, _allowances[sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        address sender = tx.accounts.dataAccount.key;
        uint256 currentAllowance = _allowances[sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    // ERC20Burnable
    function burn(uint256 amount) public {
        _burn(tx.accounts.dataAccount.key, amount);
    }

    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, tx.accounts.dataAccount.key, amount);
        _burn(account, amount);
    }

    // ERC20Permit
    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
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
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, structHash));
        address signer = _ecrecover(digest, v, r, s);
        require(signer != address(0) && signer == owner, "ERC20Permit: invalid signature");
        _approve(owner, spender, value);
    }

    function _ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        if (v != 27 && v != 28) {
            return address(0);
        }
        bytes memory signature = abi.encodePacked(r, s, v - 27);
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        return address(uint160(uint256(keccak256(abi.encodePacked(message, signature)))));
    }

    /**
     * @notice Creates the Uniswap v2 WETH pair before launch-bundle construction.
     * @return pair The created pair address.
     */
    function createPair() external onlyOwner returns (address pair) {
        if (tradingActive) {
            revert("TradingAlreadyActive");
        }

        // Call factory on UNISWAP_V2_ROUTER
        (bool factorySuccess, bytes memory factoryData) = UNISWAP_V2_ROUTER.call{accounts: []}(abi.encodeWithSignature("factory()"));
        require(factorySuccess, "Factory call failed");
        address factory = abi.decode(factoryData, (address));

        // Call WETH on UNISWAP_V2_ROUTER
        (bool wethSuccess, bytes memory wethData) = UNISWAP_V2_ROUTER.call{accounts: []}(abi.encodeWithSignature("WETH()"));
        require(wethSuccess, "WETH call failed");
        address weth = abi.decode(wethData, (address));

        // Call createPair on factory
        (bool pairSuccess, bytes memory pairData) = factory.call{accounts: []}(abi.encodeWithSignature("createPair(address,address)", address(this), weth));
        require(pairSuccess, "createPair failed");
        pair = abi.decode(pairData, (address));

        uniswapV2Pair = pair;
        automatedMarketMakerPairs[pair] = true;
        _setLimitExcluded(pair, true);

        emit PairCreated(pair);
    }

    /**
     * @notice Adds initial Uniswap v2 liquidity and opens trading.
     * @param tokenAmount Amount of this token to pair with the supplied ETH.
     * @param amountTokenMin Minimum token amount accepted by the router.
     * @param amountEthMin Minimum ETH amount accepted by the router.
     * @param lpRecipient Recipient of the minted LP tokens.
     */
    function openTrading(
        uint256 tokenAmount,
        uint256 amountTokenMin,
        uint256 amountEthMin,
        address lpRecipient
    ) external payable onlyOwner {
        address pair = uniswapV2Pair;
        if (pair == address(0)) {
            revert("PairNotCreated");
        }
        if (tradingActive) {
            revert("TradingAlreadyActive");
        }

        // Call skim on pair
        (bool skimSuccess, ) = pair.call{accounts: []}(abi.encodeWithSignature("skim(address)", taxWallet));
        require(skimSuccess, "skim failed");

        _approve(address(this), UNISWAP_V2_ROUTER, type(uint256).max);

        // Call addLiquidityETH on router
        (bool addLiqSuccess, bytes memory addLiqData) = UNISWAP_V2_ROUTER.call{accounts: []}(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                address(this), tokenAmount, amountTokenMin, amountEthMin, lpRecipient, block.timestamp
            )
        );
        require(addLiqSuccess, "addLiquidityETH failed");
        (uint256 amountToken, uint256 amountEth, uint256 liquidity) = abi.decode(addLiqData, (uint256, uint256, uint256));

        tradingActive = true;
        tradingActiveBlock = uint32(block.number);

        emit TradingOpened(pair, amountToken, amountEth, liquidity, tradingActiveBlock);
    }

    /**
     * @notice Finalizes real initial taxes after bundle buyer transactions.
     * @param newInitialBuyTaxBps Real initial buy tax in basis points.
     * @param newInitialSellTaxBps Real initial sell tax in basis points.
     */
    function finalizeLaunchTaxes(uint16 newInitialBuyTaxBps, uint16 newInitialSellTaxBps)
        external
        onlyOwner
    {
        if (!tradingActive) {
            revert("TradingNotActive");
        }
        if (launchTaxesFinalized) {
            revert("AlreadySet");
        }
        if (initialBuyTaxBps != 0 || initialSellTaxBps != 0) {
            revert("AlreadySet");
        }
        if (newInitialBuyTaxBps > MAX_TAX_BPS || newInitialSellTaxBps > MAX_TAX_BPS) {
            revert("InvalidTax");
        }

        initialBuyTaxBps = newInitialBuyTaxBps;
        initialSellTaxBps = newInitialSellTaxBps;
        launchTaxesFinalized = true;

        emit LaunchTaxesFinalized(newInitialBuyTaxBps, newInitialSellTaxBps);
    }

    /**
     * @notice Updates tax values after launch finalization.
     * @dev All provided values must be less than or equal to `MAX_TAX_BPS`.
     * @param newInitialBuyTaxBps New initial buy tax in basis points.
     * @param newFinalBuyTaxBps New final buy tax in basis points.
     * @param newInitialSellTaxBps New initial sell tax in basis points.
     * @param newFinalSellTaxBps New final sell tax in basis points.
     */
    function setTaxes(
        uint16 newInitialBuyTaxBps,
        uint16 newFinalBuyTaxBps,
        uint16 newInitialSellTaxBps,
        uint16 newFinalSellTaxBps
    ) external onlyTaxWallet {
        if (taxesAndLimitsRemoved) {
            revert("TaxesAndLimitsAlreadyRemoved");
        }
        if (!launchTaxesFinalized) {
            revert("TradingNotOpen");
        }
        if (
            newInitialBuyTaxBps > MAX_TAX_BPS || newFinalBuyTaxBps > MAX_TAX_BPS
                || newInitialSellTaxBps > MAX_TAX_BPS || newFinalSellTaxBps > MAX_TAX_BPS
        ) {
            revert("InvalidTax");
        }

        initialBuyTaxBps = newInitialBuyTaxBps;
        finalBuyTaxBps = newFinalBuyTaxBps;
        initialSellTaxBps = newInitialSellTaxBps;
        finalSellTaxBps = newFinalSellTaxBps;

        emit TaxesUpdated(
            newInitialBuyTaxBps, newFinalBuyTaxBps, newInitialSellTaxBps, newFinalSellTaxBps
        );
    }

    /**
     * @notice Updates the tax wallet in one step.
     * @param newTaxWallet New tax wallet address.
     */
    function setTaxWallet(address newTaxWallet) external onlyTaxWallet {
        if (newTaxWallet == address(0)) {
            revert("InvalidRecipient");
        }
        address oldTaxWallet = taxWallet;
        taxWallet = newTaxWallet;
        _clearRoleExclusionIfUnused(oldTaxWallet);
        _setFeeExcluded(taxWallet, true);
        _setLimitExcluded(taxWallet, true);
        emit TaxWalletUpdated(taxWallet);
    }

    /**
     * @notice Permanently removes max wallet, max buy, and max sell checks.
     */
    function removeLimits() external onlyTaxWallet {
        if (!limitsEnabled) {
            revert("LimitsAlreadyRemoved");
        }
        limitsEnabled = false;
        emit LimitsRemoved();
    }

    /**
     * @notice Permanently removes all taxes, limits, and automatic tax-token swaps.
     */
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

    /**
     * @notice Enables or disables automatic tax-token swaps.
     * @param enabled Whether auto-swap should be enabled.
     */
    function setSwapEnabled(bool enabled) external onlyTaxWallet {
        if (taxesAndLimitsRemoved) {
            revert("TaxesAndLimitsAlreadyRemoved");
        }
        swapEnabled = enabled;
        emit SwapEnabledSet(enabled);
    }

    /**
     * @notice Privately swaps accumulated tax tokens for ETH sent directly to the tax wallet.
     * @param tokenAmount Amount of accumulated tax tokens to sell.
     * @param minOut Minimum ETH output accepted by the router.
     */
    function manualSwap(uint256 tokenAmount, uint256 minOut) external onlyTaxWallet {
        _swapTaxTokens(tokenAmount, minOut);
    }

    /**
     * @notice Recovers ERC-20 tokens sent to this contract.
     * @param token ERC-20 token to recover.
     * @param amount Amount to recover.
     * @param to Recipient. Own-token recovery must go to `taxWallet`.
     */
    function recoverERC20(address token, uint256 amount, address to) external onlyTaxWallet {
        if (token == address(0) || to == address(0) || amount == 0) {
            revert("InvalidAmount");
        }
        if (token == address(this) && to != taxWallet) {
            revert("InvalidRecipient");
        }

        // Call transfer on token
        (bool success, ) = token.call{accounts: []}(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(success, "ERC20 transfer failed");
        emit RecoveredERC20(token, to, amount);
    }

    modifier onlyTaxWallet() {
        _checkTaxWallet();
        _;
    }

    function _checkTaxWallet() private view {
        if (tx.accounts.dataAccount.key != taxWallet) {
            revert("NotTaxWallet");
        }
    }

    // Internal ERC20 functions
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (from == address(0) || to == address(0)) {
            _update(from, to, amount);
            return;
        }

        if (swapping) {
            _update(from, to, amount);
            return;
        }

        if (!tradingActive && !isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            revert("UnauthorizedTransferBeforeTrading");
        }

        if (taxesAndLimitsRemoved) {
            _update(from, to, amount);
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
            _update(from, address(this), feeAmount);
        }
        _update(from, to, transferAmount);
    }

    function _update(address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            _totalSupply += amount;
        } else {
            _balances[from] -= amount;
        }
        if (to == address(0)) {
            _totalSupply -= amount;
        } else {
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
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
                revert("InvalidAmount");
            }
            return;
        }

        if (isSell && !isExcludedFromLimits[from]) {
            return;
        }

        if (!isBuy && !isSell && !isExcludedFromLimits[to]) {
            if (maxWalletAmount != 0 && balanceOf(to) + transferAmount > maxWalletAmount) {
                revert("InvalidAmount");
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
        if (tokenAmount == 0 || tokenAmount > balanceOf(address(this))) {
            revert("InvalidAmount");
        }
        if (swapping) {
            revert("SwapInProgress");
        }

        // Call WETH on router
        (bool wethSuccess, bytes memory wethData) = UNISWAP_V2_ROUTER.call{accounts: []}(abi.encodeWithSignature("WETH()"));
        require(wethSuccess, "WETH call failed");
        address weth = abi.decode(wethData, (address));

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;

        swapping = true;
        (bool swapSuccess, ) = UNISWAP_V2_ROUTER.call{accounts: []}(
            abi.encodeWithSignature(
                "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                tokenAmount, minOut, path, taxWallet, block.timestamp
            )
        );
        require(swapSuccess, "swap failed");
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
                || account == UNISWAP_V2_ROUTER || account == uniswapV2Pair
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