// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniswapV2Factory } from "../interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "../interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "../interfaces/IUniswapV2Router02.sol";

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

    /**
     * @notice Deploys a configured Uniswap v2 launch token.
     * @param config Token metadata, launch allocation, authorities, tax, limits, and clog settings.
     */
    constructor(LaunchTokenConfig memory config)
        ERC20(config.name, config.symbol)
        ERC20Permit(config.name)
        Ownable(msg.sender)
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

    /**
     * @notice Returns the configured display decimals for the token.
     * @return Token decimals.
     */
    function decimals() public view override returns (uint8) {
        return TOKEN_DECIMALS;
    }

    /**
     * @notice Creates the Uniswap v2 WETH pair before launch-bundle construction.
     * @return pair The created pair address.
     */
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

    /**
     * @notice Finalizes real initial taxes after bundle buyer transactions.
     * @param newInitialBuyTaxBps Real initial buy tax in basis points.
     * @param newInitialSellTaxBps Real initial sell tax in basis points.
     */
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

    /**
     * @notice Updates the tax wallet in one step.
     * @param newTaxWallet New tax wallet address.
     */
    function setTaxWallet(address newTaxWallet) external onlyTaxWallet {
        if (newTaxWallet == address(0)) revert InvalidRecipient();
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
        if (!limitsEnabled) revert LimitsAlreadyRemoved();
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
        if (taxesAndLimitsRemoved) revert TaxesAndLimitsAlreadyRemoved();
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