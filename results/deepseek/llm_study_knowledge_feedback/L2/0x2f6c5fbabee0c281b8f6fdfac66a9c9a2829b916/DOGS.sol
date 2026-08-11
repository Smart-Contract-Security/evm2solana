// SPDX-License-Identifier: MIT

import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

library SafeMath {
    function add(uint64 a, uint64 b) internal pure returns (uint64) {
        uint64 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint64 a, uint64 b) internal pure returns (uint64) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint64 a, uint64 b, string memory errorMessage) internal pure returns (uint64) {
        require(b <= a, errorMessage);
        uint64 c = a - b;
        return c;
    }

    function mul(uint64 a, uint64 b) internal pure returns (uint64) {
        if (a == 0) {
            return 0;
        }
        uint64 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint64 a, uint64 b) internal pure returns (uint64) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint64 a, uint64 b, string memory errorMessage) internal pure returns (uint64) {
        require(b > 0, errorMessage);
        uint64 c = a / b;
        return c;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
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
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint64 amountIn,
        uint64 amountOutMin,
        address[] calldata path,
        address to,
        uint64 deadline
    ) external;
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function addLiquidityETH(
        address token,
        uint64 amountTokenDesired,
        uint64 amountTokenMin,
        uint64 amountETHMin,
        address to,
        uint64 deadline
    ) external returns (uint64 amountToken, uint64 amountETH, uint64 liquidity);
}

contract DOGS is Context, IERC20, Ownable {
    using SafeMath for uint64;
    mapping (address => uint64) private _balances;
    mapping (address => mapping (address => uint64)) private _allowances;
    mapping (address => bool) private isExile;
    mapping (address => bool) public marketPair;
    address private _taxWallet;
    uint64 firstBlock;

    uint64 private _initialBuyTax=250;
    uint64 private _initialSellTax=250;
    uint64 private _finalBuyTax=0;
    uint64 private _finalSellTax=0;

    uint64 private _reduceBuyTaxAt=10;

    uint64 private _reduceSellTaxAt=10;
    uint64 private _preventSwapBefore=50;
    uint64 private _buyCount= 0;
    uint64 private sellCount = 0;
    uint64 private lastSellBlock = 0;

    uint8 private constant _decimals = 9;
    uint64 private constant _tTotal = 420690000000 * 10**_decimals;
    string private constant _name = "Dogs in the Ethereum World";
    string private constant _symbol = "DOGS";
    uint64 public _maxTxAmount =   4206900000 * 10**_decimals;
    uint64 public _maxWalletSize = 4206900000 * 10**_decimals;
    uint64 public _taxSwapThreshold= 42069000 * 10**_decimals;
    uint64 public _maxTaxSwap= 4206900000 * 10**_decimals;

    address private uniswapV2Router;
    address public uniswapV2Pair;
    bool private tradingOpen;
    uint64 public caBlock = 5;
    bool private inSwap = false;
    bool private swapEnabled = false;
    bool public caStop = true;

    event MaxTxAmountUpdated(uint64 _maxTxAmount);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor () {
        _taxWallet = _msgSender();
        _balances[_msgSender()] = _tTotal;
        isExile[owner()] = true;
        isExile[address(this)] = true;
        isExile[address(uniswapV2Pair)] = true;
        
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint64) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint64) {
        return _balances[account];
    }

    function transfer(address recipient, uint64 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint64 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint64 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint64 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint64 taxAmount=0;

        if (from != owner() && to != owner()) {
            taxAmount = amount.mul((_buyCount> _reduceBuyTaxAt)? _finalBuyTax: _initialBuyTax).div(1000);

            if (marketPair[from] && to != uniswapV2Router && ! isExile[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");

                if (firstBlock + 3  > block.number) {
                    require(!isContract(to));
                }
                _buyCount++;
            }

            if (!marketPair[to] && ! isExile[to]) {
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
            }

            if(marketPair[to] && from!= address(this) ){
                taxAmount = amount.mul((_buyCount> _reduceSellTaxAt)? _finalSellTax: _initialSellTax).div(1000);
            }

	    if (!marketPair[from] && !marketPair[to] && from!= address(this) ) {
                taxAmount = 0;
            }

            uint64 contractTokenBalance = balanceOf(address(this));
            if (caStop && !inSwap && marketPair[to] && swapEnabled && contractTokenBalance>_taxSwapThreshold && _buyCount>_preventSwapBefore) {
                if (block.number > lastSellBlock) {
                    sellCount = 0;
                }
                require(sellCount < caBlock, "CA balance sell");
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxTaxSwap)));
                uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
                if(contractETHBalance > 0) {
                    sendETHToFee(tx.accounts.dataAccount.lamports);
                }
                sellCount++;
                lastSellBlock = block.number;
            }

            else if(!inSwap && marketPair[to] && swapEnabled && contractTokenBalance>_taxSwapThreshold && _buyCount>_preventSwapBefore) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxTaxSwap)));
                uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
                if(contractETHBalance > 0) {
                    sendETHToFee(tx.accounts.dataAccount.lamports);
                }
            }
        }

        if(taxAmount>0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }


    function min(uint64 a, uint64 b) private pure returns (uint64){
      return (a>b)?b:a;
    }

    function isContract(address account) private view returns (bool) {
        AccountInfo memory accInfo = tx.accounts.accountInfo(account);
        return accInfo.executable;
    }

    function swapTokensForEth(uint64 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IUniswapV2Router02(uniswapV2Router).WETH();
        _approve(address(this), uniswapV2Router, tokenAmount);
        IUniswapV2Router02(uniswapV2Router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function rescueStuckETH() external onlyOwner {
        _taxWallet.transfer(tx.accounts.dataAccount.lamports);
    }

    function rescueStuckERC20Tokens(address _tokenAddr, uint64 _amount) external onlyOwner {
        IERC20(_tokenAddr).transfer(_taxWallet, _amount);
    }

    function exileW_Restriction() external onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize=_tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function sendETHToFee(uint64 amount) private {
        _taxWallet.transfer(amount);
    }

    function enableTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), uniswapV2Router, _tTotal);
        uniswapV2Pair = IUniswapV2Factory(IUniswapV2Router02(uniswapV2Router).factory()).createPair(address(this), IUniswapV2Router02(uniswapV2Router).WETH());
        marketPair[uniswapV2Pair] = true;
        isExile[uniswapV2Pair] = true;
        IUniswapV2Router02(uniswapV2Router).addLiquidityETH(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(uniswapV2Router, type(uint64).max);
        swapEnabled = true;
        tradingOpen = true;
        firstBlock = block.number;
    }
}