// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * --- BRAND IDENTITY ---
 * Brand: House Nouveau Riche
 * Token: The Veblen Standard ($VBLN)
 * Launch Date: July 24th
 *
 * --- TECHNICAL SPECIFICATIONS ---
 * Security: Anti-Bot, Anti-Whale, Reentrancy Protection
 * Revenue: Fee-on-transfer (Tax) with Auto-Swap to ETH
 * Governance: Emergency Pause and Administrative Limit Controls
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// --- INTERFACES ---
interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract VeblenStandard is
    ERC20,
    ERC20Burnable,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    // --- PHILOSOPHY ---
    string public constant PHILOSOPHY =
        "Conspicuous Consumption";

    string public constant ISSUER =
        "House Nouveau Riche";

    // --- ECONOMICS ---
    uint256 public maxWalletSize;
    uint256 public maxTxAmount;
    uint256 public taxFee;

    // --- REVENUE ENGINE ---
    uint256 public swapThreshold;

    bool public swapEnabled = false;

    bool private inSwap;

    // --- DEX INTEGRATION ---
    IUniswapV2Router02 public uniswapV2Router;

    address public uniswapV2Pair;

    // --- ANTIBOT ---
    bool public transferDelayEnabled = true;

    mapping(address => uint256)
        private lastTradeBlock;

    // --- WALLETS ---
    address public marketingWallet;

    // --- MAPPINGS ---
    mapping(address => bool)
        public isExcludedFromLimits;

    // --- EVENTS ---
    event MaxLimitsRemoved(
        uint256 timestamp
    );

    event TradingOpened(
        uint256 timestamp
    );

    event MaxWalletUpdated(
        uint256 newLimit
    );

    event MaxTxUpdated(
        uint256 newLimit
    );

    event TaxFeeUpdated(
        uint256 newFee
    );

    event SwapThresholdUpdated(
        uint256 newThreshold
    );

    event TransferDelayUpdated(
        bool enabled
    );

    event ExcludedFromLimits(
        address indexed account,
        bool isExcluded
    );

    event MarketingWalletUpdated(
        address indexed newWallet
    );

    event SwapEnabledUpdated(
        bool enabled
    );

    event ManualSwapExecuted(
        uint256 tokenAmount
    );

    event TokensRescued(
        address indexed token,
        uint256 amount
    );

    event ETHRescued(
        uint256 amount
    );

    event SwapFailed(
        string reason
    );

    event SwapSuccessful(
        uint256 amountIn
    );

    // --- SWAP LOCK ---
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // --- CONSTRUCTOR ---
    constructor(
        address initialOwner,
        address routerAddress
    )
        ERC20(
            "The Veblen Standard",
            "VBLN"
        )
        Ownable(initialOwner)
    {
        // Mint Supply
        _mint(
            initialOwner,
            10_000_000 * 10 ** decimals()
        );

        // Initial Settings
        marketingWallet = initialOwner;

        taxFee = 20;

        swapThreshold =
            5_000 *
            10 ** decimals();

        // Limits
        maxWalletSize =
            100_000 *
            10 ** decimals();

        maxTxAmount =
            50_000 *
            10 ** decimals();

        // Router Setup
        IUniswapV2Router02 router =
            IUniswapV2Router02(
                routerAddress
            );

        uniswapV2Router = router;

        uniswapV2Pair =
            IUniswapV2Factory(
                router.factory()
            ).createPair(
                    address(this),
                    router.WETH()
                );

        // Exclusions
        isExcludedFromLimits[
            initialOwner
        ] = true;

        isExcludedFromLimits[
            address(this)
        ] = true;

        isExcludedFromLimits[
            address(0)
        ] = true;

        isExcludedFromLimits[
            routerAddress
        ] = true;

        isExcludedFromLimits[
            uniswapV2Pair
        ] = true;

        // Start Paused
        _pause();
    }

    // Accept ETH
    receive() external payable {}

    // --- TRANSFER ENGINE ---
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        // Skip limits during mint/burn
        if (
            from == address(0) ||
            to == address(0)
        ) {
            super._update(
                from,
                to,
                value
            );

            return;
        }

        // Trading pause protection
        if (paused()) {
            require(
                isExcludedFromLimits[
                    from
                ] ||
                    isExcludedFromLimits[
                        to
                    ],
                "Veblen: Trading Paused"
            );
        }

        // Limits
        if (
            !paused() &&
            !isExcludedFromLimits[
                from
            ] &&
            !isExcludedFromLimits[to]
        ) {
            // Transfer Delay
            if (
                transferDelayEnabled
            ) {
                address trader = from ==
                    uniswapV2Pair
                    ? to
                    : from;

                if (
                    trader !=
                    address(
                        uniswapV2Router
                    ) &&
                    trader !=
                    uniswapV2Pair
                ) {
                    require(
                        lastTradeBlock[
                            trader
                        ] < block.number,
                        "Veblen: One transfer per block"
                    );

                    lastTradeBlock[
                        trader
                    ] = block.number;
                }
            }

            // Max TX
            if (
                from ==
                uniswapV2Pair ||
                to ==
                uniswapV2Pair
            ) {
                require(
                    value <=
                        maxTxAmount,
                    "Veblen: Max TX exceeded"
                );
            }

            // Max Wallet
            if (
                to !=
                uniswapV2Pair &&
                to !=
                address(
                    uniswapV2Router
                )
            ) {
                require(
                    balanceOf(to) +
                        value <=
                        maxWalletSize,
                    "Veblen: Max wallet exceeded"
                );
            }
        }

        uint256 finalAmount = value;

        bool takeFee = (
            !paused() &&
            (
                from ==
                    uniswapV2Pair ||
                    to ==
                    uniswapV2Pair
            ) &&
            !isExcludedFromLimits[
                from
            ] &&
            !isExcludedFromLimits[to]
        );

        // Auto Swap
        uint256 contractBalance =
            balanceOf(
                address(this)
            );

        if (
            contractBalance >=
            swapThreshold &&
            swapEnabled &&
            to ==
            uniswapV2Pair &&
            !inSwap &&
            !paused() &&
            !isExcludedFromLimits[
                from
            ]
        ) {
            _swapTokensForETH(
                _min(
                    contractBalance,
                    swapThreshold
                )
            );
        }

        // Take Tax
        if (takeFee) {
            uint256 taxAmount = (
                value * taxFee
            ) / 100;

            if (taxAmount > 0) {
                super._update(
                    from,
                    address(this),
                    taxAmount
                );

                finalAmount =
                    value -
                    taxAmount;
            }
        }

        super._update(
            from,
            to,
            finalAmount
        );
    }

    // --- SWAP TOKENS FOR ETH ---
    function _swapTokensForETH(
        uint256 tokenAmount
    ) private lockTheSwap {
        if (tokenAmount == 0)
            return;

        address[]
            memory path = new address[](
                2
            );

        path[0] = address(this);

        path[1] = uniswapV2Router
            .WETH();

        _approve(
            address(this),
            address(
                uniswapV2Router
            ),
            tokenAmount
        );

        try
            uniswapV2Router
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    tokenAmount,
                    0,
                    path,
                    marketingWallet,
                    block.timestamp
                )
        {
            emit SwapSuccessful(
                tokenAmount
            );
        } catch Error(
            string memory reason
        ) {
            emit SwapFailed(
                reason
            );
        } catch {
            emit SwapFailed(
                "Low-level swap error"
            );
        }
    }

    // --- HELPERS ---
    function _min(
        uint256 a,
        uint256 b
    )
        private
        pure
        returns (uint256)
    {
        return a < b ? a : b;
    }

    // --- ADMIN FUNCTIONS ---
    function openTrading()
        external
        onlyOwner
    {
        _unpause();

        emit TradingOpened(
            block.timestamp
        );
    }

    function pause()
        external
        onlyOwner
    {
        _pause();
    }

    function removeLimits()
        external
        onlyOwner
    {
        maxWalletSize =
            totalSupply();

        maxTxAmount =
            totalSupply();

        transferDelayEnabled = false;

        emit MaxLimitsRemoved(
            block.timestamp
        );
    }

    function updateMaxWallet(
        uint256 newNum
    ) external onlyOwner {
        uint256 newLimit = newNum *
            10 ** decimals();

        require(
            newLimit >=
                totalSupply() /
                    1000,
            "Limit too low"
        );

        maxWalletSize = newLimit;

        emit MaxWalletUpdated(
            newLimit
        );
    }

    function updateMaxTx(
        uint256 newNum
    ) external onlyOwner {
        uint256 newLimit = newNum *
            10 ** decimals();

        require(
            newLimit >=
                totalSupply() /
                    1000,
            "Limit too low"
        );

        maxTxAmount = newLimit;

        emit MaxTxUpdated(
            newLimit
        );
    }

    function updateTaxFee(
        uint256 newFee
    ) external onlyOwner {
        require(
            newFee <= 30,
            "Max tax is 30%"
        );

        taxFee = newFee;

        emit TaxFeeUpdated(
            newFee
        );
    }

    function updateSwapThreshold(
        uint256 newAmount
    ) external onlyOwner {
        swapThreshold =
            newAmount *
            10 **
            decimals();

        emit SwapThresholdUpdated(
            swapThreshold
        );
    }

    function setSwapEnabled(
        bool enabled
    ) external onlyOwner {
        swapEnabled = enabled;

        emit SwapEnabledUpdated(
            enabled
        );
    }

    function manualSwap()
        external
        onlyOwner
    {
        uint256 contractBalance =
            balanceOf(
                address(this)
            );

        require(
            contractBalance > 0,
            "No tokens"
        );

        _swapTokensForETH(
            contractBalance
        );

        emit ManualSwapExecuted(
            contractBalance
        );
    }

    // --- RECOVERY ---
    function rescueTokens(
        address tokenAddress,
        address to
    ) external onlyOwner {
        require(
            tokenAddress !=
                address(this),
            "Cannot rescue VBLN"
        );

        uint256 amount = IERC20(
            tokenAddress
        ).balanceOf(address(this));

        IERC20(tokenAddress)
            .transfer(to, amount);

        emit TokensRescued(
            tokenAddress,
            amount
        );
    }

    function rescueETH()
        external
        onlyOwner
        nonReentrant
    {
        uint256 balance = address(
            this
        ).balance;

        require(
            balance > 0,
            "No ETH"
        );

        (
            bool success,

        ) = payable(msg.sender)
                .call{
                value: balance
            }("");

        require(
            success,
            "Transfer failed"
        );

        emit ETHRescued(
            balance
        );
    }

    function toggleTransferDelay(
        bool enabled
    ) external onlyOwner {
        transferDelayEnabled = enabled;

        emit TransferDelayUpdated(
            enabled
        );
    }

    function excludeFromLimits(
        address account,
        bool excluded
    ) external onlyOwner {
        isExcludedFromLimits[
            account
        ] = excluded;

        emit ExcludedFromLimits(
            account,
            excluded
        );
    }

    function updateMarketingWallet(
        address newWallet
    ) external onlyOwner {
        require(
            newWallet !=
                address(0) &&
                newWallet !=
                address(this),
            "Invalid wallet"
        );

        marketingWallet = newWallet;

        isExcludedFromLimits[
            newWallet
        ] = true;

        emit MarketingWalletUpdated(
            newWallet
        );
    }
}