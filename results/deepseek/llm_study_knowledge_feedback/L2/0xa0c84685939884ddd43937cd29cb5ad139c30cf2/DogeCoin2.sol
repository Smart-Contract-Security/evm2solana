import {AccountMeta, AccountInfo} from 'solana';

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

contract Ownable is Context {
    address private _owner;
    address private _previousOwner;
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

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
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

    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint64 amountTokenDesired,
        uint64 amountTokenMin,
        uint64 amountETHMin,
        address to,
        uint64 deadline
    ) external returns (uint64 amountToken, uint64 amountETH, uint64 liquidity);
}

contract DogeCoin2 is Context, IERC20, Ownable {
    using SafeMath for uint64;

    string private constant _name = "Caesar";
    string private constant _symbol = "DOGE2";
    uint8 private constant _decimals = 9;

    mapping(address => uint64) private _rOwned;
    mapping(address => uint64) private _tOwned;
    mapping(address => mapping(address => uint64)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    uint64 private constant MAX = ~uint64(0);
    uint64 private constant _tTotal = 420690000000 * 10**9;
    uint64 private _rTotal = (MAX - (MAX % _tTotal));
    uint64 private _tFeeTotal;
    uint64 private _redisFeeOnBuy = 0;
    uint64 private _taxFeeOnBuy = 0;
    uint64 private _redisFeeOnSell = 0;
    uint64 private _taxFeeOnSell = 0;

    uint64 private _redisFee = _redisFeeOnSell;
    uint64 private _taxFee = _taxFeeOnSell;

    uint64 private _previousredisFee = _redisFee;
    uint64 private _previoustaxFee = _taxFee;

    mapping(address => bool) public bots;
    mapping(address => uint64) public _buyMap;
    address private _developmentAddress;
    address private _marketingAddress;

    address public uniswapV2Router;
    address public uniswapV2Pair;

    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = true;

    uint64 public _maxTxAmount = 420690000000 * 10**9;
    uint64 public _maxWalletSize = 420690000000 * 10**9;
    uint64 public _swapTokensAtAmount = 420690000 * 10**9;

    event MaxTxAmountUpdated(uint64 _maxTxAmount);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() {
        _rOwned[_msgSender()] = _rTotal;

        // On Solana, we cannot use Ethereum addresses or call external contracts in constructor without accounts.
        // The router and pair addresses must be set after deployment via a separate initialization function.
        // For now, we leave them as zero addresses and provide an initialize function.
        uniswapV2Router = address(0);
        uniswapV2Pair = address(0);

        _developmentAddress = _msgSender();
        _marketingAddress = _msgSender();

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_developmentAddress] = true;
        _isExcludedFromFee[_marketingAddress] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    // Initialize function to set router and pair addresses after deployment
    function initialize(address _router, address _pair) public onlyOwner {
        require(uniswapV2Router == address(0), "Already initialized");
        uniswapV2Router = _router;
        uniswapV2Pair = _pair;
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
        return tokenFromReflection(_rOwned[account]);
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

    function tokenFromReflection(uint64 rAmount) private view returns (uint64) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint64 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function removeAllFee() private {
        if (_redisFee == 0 && _taxFee == 0) return;
        _previousredisFee = _redisFee;
        _previoustaxFee = _taxFee;
        _redisFee = 0;
        _taxFee = 0;
    }

    function restoreAllFee() private {
        _redisFee = _previousredisFee;
        _taxFee = _previoustaxFee;
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

        if (from != owner() && to != owner()) {
            if (!tradingOpen) {
                require(from == owner(), "TOKEN: This account cannot send tokens until trading is enabled");
            }
            require(amount <= _maxTxAmount, "TOKEN: Max Transaction Limit");
            require(!bots[from] && !bots[to], "TOKEN: Your account is blacklisted!");

            if (to != uniswapV2Pair) {
                require(balanceOf(to) + amount < _maxWalletSize, "TOKEN: Balance exceeds wallet size!");
            }

            uint64 contractTokenBalance = balanceOf(address(this));
            bool canSwap = contractTokenBalance >= _swapTokensAtAmount;

            if (contractTokenBalance >= _maxTxAmount) {
                contractTokenBalance = _maxTxAmount;
            }

            if (canSwap && !inSwap && from != uniswapV2Pair && swapEnabled && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
                swapTokensForEth(contractTokenBalance);
                uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
                if (contractETHBalance > 0) {
                    sendETHToFee(contractETHBalance);
                }
            }
        }

        bool takeFee = true;

        if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
            takeFee = false;
        } else {
            if (from == uniswapV2Pair && to != uniswapV2Router) {
                _redisFee = _redisFeeOnBuy;
                _taxFee = _taxFeeOnBuy;
            }
            if (to == uniswapV2Pair && from != uniswapV2Router) {
                _redisFee = _redisFeeOnSell;
                _taxFee = _taxFeeOnSell;
            }
        }

        _tokenTransfer(from, to, amount, takeFee);
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

    function sendETHToFee(uint64 amount) private {
        // Transfer lamports directly using AccountInfo
        tx.accounts.dataAccount.lamports -= amount;
        AccountInfo marketingAccount = tx.accounts.marketingAccount;
        marketingAccount.lamports += amount;
    }

    function setTrading(bool _tradingOpen) public onlyOwner {
        tradingOpen = _tradingOpen;
    }

    function manualswap() external {
        require(_msgSender() == _developmentAddress || _msgSender() == _marketingAddress);
        uint64 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    function manualsend() external {
        require(_msgSender() == _developmentAddress || _msgSender() == _marketingAddress);
        uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
        sendETHToFee(contractETHBalance);
    }

    function blockBots(address[] memory bots_) public onlyOwner {
        for (uint64 i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }

    function unblockBot(address notbot) public onlyOwner {
        bots[notbot] = false;
    }

    function _tokenTransfer(address sender, address recipient, uint64 amount, bool takeFee) private {
        if (!takeFee) removeAllFee();
        _transferStandard(sender, recipient, amount);
        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint64 tAmount) private {
        (uint64 rAmount, uint64 rTransferAmount, uint64 rFee, uint64 tTransferAmount, uint64 tFee, uint64 tTeam) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeTeam(tTeam);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _takeTeam(uint64 tTeam) private {
        uint64 currentRate = _getRate();
        uint64 rTeam = tTeam.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rTeam);
    }

    function _reflectFee(uint64 rFee, uint64 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint64 tAmount) private view returns (uint64, uint64, uint64, uint64, uint64, uint64) {
        (uint64 tTransferAmount, uint64 tFee, uint64 tTeam) = _getTValues(tAmount, _redisFee, _taxFee);
        uint64 currentRate = _getRate();
        (uint64 rAmount, uint64 rTransferAmount, uint64 rFee) = _getRValues(tAmount, tFee, tTeam, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam);
    }

    function _getTValues(uint64 tAmount, uint64 redisFee, uint64 taxFee) private pure returns (uint64, uint64, uint64) {
        uint64 tFee = tAmount.mul(redisFee).div(100);
        uint64 tTeam = tAmount.mul(taxFee).div(100);
        uint64 tTransferAmount = tAmount.sub(tFee).sub(tTeam);
        return (tTransferAmount, tFee, tTeam);
    }

    function _getRValues(uint64 tAmount, uint64 tFee, uint64 tTeam, uint64 currentRate) private pure returns (uint64, uint64, uint64) {
        uint64 rAmount = tAmount.mul(currentRate);
        uint64 rFee = tFee.mul(currentRate);
        uint64 rTeam = tTeam.mul(currentRate);
        uint64 rTransferAmount = rAmount.sub(rFee).sub(rTeam);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint64) {
        (uint64 rSupply, uint64 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint64, uint64) {
        uint64 rSupply = _rTotal;
        uint64 tSupply = _tTotal;
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function setFee(uint64 redisFeeOnBuy, uint64 redisFeeOnSell, uint64 taxFeeOnBuy, uint64 taxFeeOnSell) public onlyOwner {
        _redisFeeOnBuy = redisFeeOnBuy;
        _redisFeeOnSell = redisFeeOnSell;
        _taxFeeOnBuy = taxFeeOnBuy;
        _taxFeeOnSell = taxFeeOnSell;
    }

    function setMinSwapTokensThreshold(uint64 swapTokensAtAmount) public onlyOwner {
        _swapTokensAtAmount = swapTokensAtAmount;
    }

    function toggleSwap(bool _swapEnabled) public onlyOwner {
        swapEnabled = _swapEnabled;
    }

    function setMaxTxnAmount(uint64 maxTxAmount) public onlyOwner {
        _maxTxAmount = maxTxAmount;
    }

    function setMaxWalletSize(uint64 maxWalletSize) public onlyOwner {
        _maxWalletSize = maxWalletSize;
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for (uint64 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = excluded;
        }
    }
}