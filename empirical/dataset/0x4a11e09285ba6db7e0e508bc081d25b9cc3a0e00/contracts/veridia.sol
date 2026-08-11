// SPDX-License-Identifier: MIT
// https://vitalik.eth.limo/w/html/ch1.html
// https://vitalik.eth.limo/w/html/ch2.html
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

interface IWETH9 {
    function withdraw(uint256 amount) external;
}

contract Veridia is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1e9 * 1e18

    // Uniswap V3 SwapRouter02 + WETH9 (Ethereum mainnet). Used to liquidate the
    // contract's treasury allocation into ETH for the dev wallet on sells.
    address public constant SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public maxTransactionAmount;
    uint256 public maxWalletAmount;
    bool public limitsEnabled = true;

    // No manual trading gate: trading turns on automatically the first time
    // liquidity is seeded into a registered pair. `launchBlock` anchors the
    // anti-snipe window that prevents the LP add from being front-run.
    bool public tradingActive;
    uint256 public launchBlock;
    uint256 public deadBlocks = 2; // buys revert for launchBlock .. launchBlock+deadBlocks

    // Treasury auto-sell: the contract starts holding 10% of supply and dribbles
    // it out to the dev wallet (as ETH) whenever sells come in.
    address public devWallet;
    bool public swapEnabled = true;
    uint256 public swapThreshold; // min contract balance before a swap fires
    uint256 public maxSwapAmount; // cap per swap, to bound price impact
    uint24 public poolFee = 10000; // fee tier of the VERIDIA/WETH pool (1%)
    bool private inSwap;

    // Addresses that ignore limits + trading gate (owner, contract, router, position manager).
    mapping(address => bool) public isExcludedFromLimits;
    // AMM pairs/pools. A `to` that is an AMM pair is a SELL/add-liquidity, so maxWallet is not applied to it.
    mapping(address => bool) public isAMMPair;

    event TradingActivated(uint256 launchBlock);
    event LimitsRemoved();
    event LimitsUpdated(uint256 maxTransactionAmount, uint256 maxWalletAmount);
    event PairSet(address indexed pair, bool value);
    event ExcludedFromLimits(address indexed account, bool value);
    event DevWalletUpdated(address indexed devWallet);
    event SwapBackSettingsUpdated(bool enabled, uint256 threshold, uint256 maxAmount);
    event SwapBack(uint256 tokensSwapped, uint256 ethToDev);

    modifier lockSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() ERC20("Vitalik's Veridia", "VERIDIA") Ownable(msg.sender) {
        maxTransactionAmount = (TOTAL_SUPPLY * 1) / 100; // 1%
        maxWalletAmount = (TOTAL_SUPPLY * 2) / 100; // 2%
        swapThreshold = (TOTAL_SUPPLY * 5) / 10000; // 0.05%
        maxSwapAmount = (TOTAL_SUPPLY * 5) / 1000; // 0.5%

        devWallet = msg.sender;

        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[address(0)] = true;
        isExcludedFromLimits[0x000000000000000000000000000000000000dEaD] = true;

        // 10% of supply is held by the contract as a treasury to be sold off to
        // the dev wallet over time; the remaining 90% goes to the deployer for LP.
        uint256 treasury = (TOTAL_SUPPLY * 10) / 100;
        _mint(address(this), treasury);
        _mint(msg.sender, TOTAL_SUPPLY - treasury);
    }

    receive() external payable {}

    // --- Owner controls ---------------------------------------------------

    /// @notice Register/unregister a Uniswap V3 pool (or any AMM pair) for limit handling.
    function setPair(address pair, bool value) external onlyOwner {
        require(pair != address(0), "Zero pair");
        isAMMPair[pair] = value;
        emit PairSet(pair, value);
    }

    function setExcludedFromLimits(address account, bool value) external onlyOwner {
        isExcludedFromLimits[account] = value;
        emit ExcludedFromLimits(account, value);
    }

    /// @notice Adjust limits. Values are in whole tokens (e.g. 5_000_000), converted to wei here.
    function setLimits(uint256 maxTxTokens, uint256 maxWalletTokens) external onlyOwner {
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
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        emit LimitsRemoved();
    }

    /// @notice Length of the anti-snipe window (in blocks). Settable only before
    /// launch and capped, so it can't be turned into a honeypot after the fact.
    function setDeadBlocks(uint256 blocks_) external onlyOwner {
        require(!tradingActive, "Already launched");
        require(blocks_ <= 10, "deadBlocks too high");
        deadBlocks = blocks_;
    }

    /// @notice Fee tier of the VERIDIA/WETH pool used for treasury swaps. Pre-launch only.
    function setPoolFee(uint24 fee) external onlyOwner {
        require(!tradingActive, "Already launched");
        poolFee = fee;
    }

    function setDevWallet(address wallet_) external onlyOwner {
        require(wallet_ != address(0), "Zero dev wallet");
        devWallet = wallet_;
        emit DevWalletUpdated(wallet_);
    }

    /// @notice Tune the treasury auto-sell. Threshold/maxAmount are in whole tokens.
    function setSwapBackSettings(bool enabled, uint256 thresholdTokens, uint256 maxAmountTokens) external onlyOwner {
        swapEnabled = enabled;
        swapThreshold = thresholdTokens * 1e18;
        maxSwapAmount = maxAmountTokens * 1e18;
        emit SwapBackSettingsUpdated(enabled, swapThreshold, maxSwapAmount);
    }

    /// @notice Recover ETH that, for any reason, did not forward to the dev wallet.
    function rescueETH() external onlyOwner {
        (bool sent, ) = payable(devWallet).call{value: address(this).balance}("");
        require(sent, "ETH rescue failed");
    }

    // --- Transfer hook (OZ v5) -------------------------------------------

    function _update(address from, address to, uint256 amount) internal override {
        // Internal treasury swaps bypass all logic to avoid recursion.
        if (inSwap) {
            super._update(from, to, amount);
            return;
        }

        // Minting (from == 0) and burning to dead are always allowed via exclusions.
        bool excluded = isExcludedFromLimits[from] || isExcludedFromLimits[to];

        // Auto-launch: trading turns on the moment an excluded address (owner /
        // position manager) seeds a registered pair with liquidity. The whole LP
        // add happens in this one tx, so there is no window to buy beforehand.
        if (!tradingActive && excluded && isAMMPair[to] && amount > 0) {
            tradingActive = true;
            launchBlock = block.number;
            emit TradingActivated(block.number);
        }

        if (!excluded) {
            require(tradingActive, "Trading not active");

            // Anti-snipe: no buys (transfers OUT of a pair) during the launch
            // dead-block window, so the LP add cannot be sniped/front-run.
            if (isAMMPair[from] && block.number <= launchBlock + deadBlocks) {
                revert("Anti-snipe window");
            }

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

        // On sells (non-excluded sender into a pair), dribble the treasury out to
        // the dev wallet as ETH. Guarded so a missing/failing router never blocks a sell.
        bool isSell = isAMMPair[to] && !isExcludedFromLimits[from];
        if (
            swapEnabled &&
            tradingActive &&
            isSell &&
            balanceOf(address(this)) >= swapThreshold &&
            SWAP_ROUTER.code.length > 0
        ) {
            _swapBack();
        }

        super._update(from, to, amount);
    }

    function _swapBack() private lockSwap {
        uint256 contractBalance = balanceOf(address(this));
        uint256 amountToSwap = contractBalance > maxSwapAmount ? maxSwapAmount : contractBalance;
        if (amountToSwap == 0) return;

        _approve(address(this), SWAP_ROUTER, amountToSwap);

        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: WETH,
            fee: poolFee,
            recipient: address(this),
            amountIn: amountToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // try/catch: a swap revert (e.g. no pool at this fee tier) must never brick trading.
        try ISwapRouter02(SWAP_ROUTER).exactInputSingle(params) returns (uint256 wethOut) {
            if (wethOut > 0) {
                try IWETH9(WETH).withdraw(wethOut) {
                    uint256 ethBal = address(this).balance;
                    if (ethBal > 0) {
                        (bool sent, ) = payable(devWallet).call{value: ethBal}("");
                        if (sent) emit SwapBack(amountToSwap, ethBal);
                    }
                } catch {}
            }
        } catch {}
    }
}
