// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
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
}

contract StandardOpenTradingToken is ERC20, Ownable {
    mapping(address => bool) public bots;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;
    bool public tradingOpen;

    event BotUpdated(address indexed account, bool isBot);
    event TradingOpened(
        address indexed pair,
        uint256 tokenAmount,
        uint256 ethAmount,
        address indexed lpRecipient
    );

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address router_,
        address[20] memory initialBots_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(router_ != address(0), "router is zero");

        uniswapV2Router = IUniswapV2Router02(router_);

        // initialSupply_ is expressed in whole tokens and scaled to 18 decimals.
        _mint(msg.sender, initialSupply_ * 10 ** decimals());

        for (uint256 i = 0; i < initialBots_.length; ++i) {
            address bot = initialBots_[i];
            require(bot != address(0), "bot is zero");
            require(bot != router_, "router cannot be bot");
            bots[bot] = true;
            emit BotUpdated(bot, true);
        }
    }

    function setBot(address account, bool isBot) external onlyOwner {
        require(!tradingOpen, "bot list locked");
        require(account != address(0), "account is zero");
        require(account != address(uniswapV2Router), "router cannot be bot");

        bots[account] = isBot;
        emit BotUpdated(account, isBot);
    }

    function openTrading(uint256 tokenAmount, address lpRecipient) external payable onlyOwner {
        require(!tradingOpen, "trading already open");
        require(tokenAmount > 0, "token amount is zero");
        require(msg.value > 0, "eth amount is zero");
        require(lpRecipient != address(0), "lp recipient is zero");

        address pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );

        uniswapV2Pair = pair;

        _transfer(msg.sender, address(this), tokenAmount);
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // Opening is atomic with liquidity add. If addLiquidityETH reverts, tradingOpen also reverts.
        tradingOpen = true;

        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            0,
            0,
            lpRecipient,
            block.timestamp
        );

        emit TradingOpened(pair, tokenAmount, msg.value, lpRecipient);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            require(!bots[from] && !bots[to], "blacklisted");

            if (!tradingOpen) {
                bool allowed =
                    from == owner() ||
                    to == owner() ||
                    from == address(this) ||
                    to == address(this);
                require(allowed, "trading is not open");
            }
        }

        super._update(from, to, value);
    }

    receive() external payable {}
}
