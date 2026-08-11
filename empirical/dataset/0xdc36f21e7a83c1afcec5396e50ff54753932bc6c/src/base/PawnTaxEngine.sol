// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PawnNFT404} from "./PawnNFT404.sol";
import {IPawnTreasury} from "../interfaces/IPawnTreasury.sol";
import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";

abstract contract PawnTaxEngine is PawnNFT404 {
    uint256 internal _initialBuyTax = 15;
    uint256 internal _initialSellTax = 20;
    uint256 internal _finalBuyTax = 3;
    uint256 internal _finalSellTax = 3;

    uint256 internal _reduceBuyTaxAt = 15;
    uint256 internal _reduceSellTaxAt = 15;
    uint256 internal _preventSwapBefore = 15;
    uint256 internal _buyCount;

    uint256 public _maxTxAmount = TOTAL_SUPPLY * 2 / 100;
    uint256 public _maxWalletSize = TOTAL_SUPPLY * 2 / 100;

    uint256 public _taxSwapThreshold = TOTAL_SUPPLY / 1000;
    uint256 public _maxTaxSwap = TOTAL_SUPPLY / 100;

    IUniswapV2Router02 internal _uniswapV2Router;
    address public uniswapV2Pair;
    address public immutable ROUTER_ADDRESS;
    bool public tradingOpen;
    bool internal inSwap;
    bool public swapEnabled;
    uint256 private sellCount;
    uint256 private lastSellBlock;

    address public immutable MARKETING_WALLET;

    mapping(address => bool) public bots;

    event MaxTxAmountUpdated(uint256 maxTx);
    event LimitsRemoved();
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event TradingOpened(address pair, uint256 liquidityEth, uint256 liquidityTokens);
    event BotAdded(address indexed bot);
    event BotRemoved(address indexed bot);
    event SkipPawnSet(address indexed holder, bool skipping);

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address marketingWallet_, address router_) {
        MARKETING_WALLET = marketingWallet_;

        address router = router_ != address(0)
            ? router_
            : 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        ROUTER_ADDRESS = router;
    }

    function _routeTaxETH(uint256 amount) internal {
        if (!IPawnTreasury(TREASURY).treasuryActive()) {
            (bool ok,) = payable(MARKETING_WALLET).call{value: amount}("");
            require(ok, "ETH to marketing wallet failed");
        } else {
            IPawnTreasury(TREASURY).receiveETH{value: amount}();
        }
    }

    function _swapTokensForEth(uint256 tokenAmount) internal lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();
        _approve(address(this), address(_uniswapV2Router), tokenAmount);
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, address(this), block.timestamp
        );
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _maybeTriggerSwap(bool isSell, address from, uint256 amount) internal {
        if (
            !inSwap && isSell && swapEnabled && !_isExcludedFromFee[from]
                && _balances[address(this)] > _taxSwapThreshold
                && _buyCount > _preventSwapBefore
        ) {
            if (block.number > lastSellBlock) sellCount = 0;
            if (sellCount < 3) {
                uint256 swapAmt =
                    _min(amount, _min(_balances[address(this)], _maxTaxSwap));
                _swapTokensForEth(swapAmt);
                uint256 ethBal = address(this).balance;
                if (ethBal > 0) _routeTaxETH(ethBal);
                sellCount++;
                lastSellBlock = block.number;
            }
        }
    }

    function openTrading() external onlyOwner {
        require(!tradingOpen, "already open");
        uint256 ethAmount = address(this).balance;
        require(ethAmount > 0, "no ETH");

        _uniswapV2Router = IUniswapV2Router02(ROUTER_ADDRESS);
        nftExempt[ROUTER_ADDRESS] = true;

        address pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this), _uniswapV2Router.WETH()
        );
        uniswapV2Pair = pair;
        nftExempt[pair] = true;

        tradingOpen = true;
        swapEnabled = true;

        uint256 tokenAmount = _balances[address(this)];
        _approve(address(this), address(_uniswapV2Router), tokenAmount);
        _uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this), tokenAmount, 0, 0, owner(), block.timestamp
        );

        IERC20(pair).approve(address(_uniswapV2Router), type(uint256).max);

        emit TradingOpened(pair, ethAmount, tokenAmount);
    }

    function buyCount() external view returns (uint256) {
        return _buyCount;
    }

    function removeLimits() external onlyOwner {
        _maxTxAmount = TOTAL_SUPPLY;
        _maxWalletSize = TOTAL_SUPPLY;
        emit LimitsRemoved();
        emit MaxTxAmountUpdated(TOTAL_SUPPLY);
    }

    function setFees(uint256 buyFee_, uint256 sellFee_) external onlyOwner {
        require(buyFee_ <= 99, "fee too high");
        require(sellFee_ <= 99, "fee too high");
        _finalBuyTax = buyFee_;
        _finalSellTax = sellFee_;
        emit FeesUpdated(buyFee_, sellFee_);
    }

    function addBots(address[] calldata bots_) external onlyOwner {
        for (uint256 i; i < bots_.length; i++) {
            bots[bots_[i]] = true;
            emit BotAdded(bots_[i]);
        }
    }

    function delBots(address[] calldata notBots_) external onlyOwner {
        for (uint256 i; i < notBots_.length; i++) {
            bots[notBots_[i]] = false;
            emit BotRemoved(notBots_[i]);
        }
    }

    function _setExempt(address addr, bool exempt_) internal {
        _isExcludedFromFee[addr] = exempt_;
        nftExempt[addr] = exempt_;
    }
}
