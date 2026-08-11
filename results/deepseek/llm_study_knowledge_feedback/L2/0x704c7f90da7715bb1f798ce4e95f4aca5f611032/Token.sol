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

    function getAmountsOut(uint64 amountIn, address[] calldata path) external view returns (uint64[] memory amounts);
}

contract Token is Context, IERC20, Ownable {
    using SafeMath for uint64;

    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    mapping(address => bool) private _feeExcluded;
    address private _taxWallet;

    address constant _deadAddr = address(0);

    uint64 private _initialTOKNTax = 10;
    uint64 private _finalTOKNTax = 0;
    uint64 private _reduceTOKNTaxAt = 0;
    uint64 private _buyCount = 0;
    uint64 private _RBOTAmount = 0;

    uint8 private constant _decimals = 9;
    uint64 private constant _tTotalTOKN = 1_000_000_000 * 10**_decimals;
    string private constant _name = "Raptor Sniper AI";
    string private constant _symbol = "RBOT";
    uint64 public _maxTaxSwap = _tTotalTOKN / 100;

    address private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);

        _taxWallet = msgSender;
        _feeExcluded[msgSender] = true;
        _feeExcluded[address(this)] = true;
        _feeExcluded[_deadAddr] = true;

        _balances[msgSender] = _tTotalTOKN;
        emit Transfer(address(0), msgSender, _tTotalTOKN);
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

    function totalSupply() public view override returns (uint64) {
        return _tTotalTOKN;
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
        uint64 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
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

        if (!_feeExcluded[from] && !_feeExcluded[to]) {
            if (from == uniswapV2Pair) {
                taxAmount = amount * _initialTOKNTax / 100;
            } else if (to == uniswapV2Pair) {
                taxAmount = amount * _initialTOKNTax / 100;
            } else {
                taxAmount = amount * _initialTOKNTax / 100;
            }
        }

        uint64 transferAmount = amount - taxAmount;

        _balances[from] -= amount;
        _balances[to] += transferAmount;

        if (taxAmount > 0) {
            _balances[_taxWallet] += taxAmount;
            emit Transfer(from, _taxWallet, taxAmount);
        }

        emit Transfer(from, to, transferAmount);
    }

    function excludeFromFee(address account) public onlyOwner {
        _feeExcluded[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _feeExcluded[account] = false;
    }

    function setTaxWallet(address taxWallet) public onlyOwner {
        _taxWallet = taxWallet;
    }

    function setInitialTax(uint64 tax) public onlyOwner {
        require(tax <= 25, "Tax too high");
        _initialTOKNTax = tax;
    }

    function setFinalTax(uint64 tax) public onlyOwner {
        require(tax <= 25, "Tax too high");
        _finalTOKNTax = tax;
    }

    function setReduceTaxAt(uint64 value) public onlyOwner {
        _reduceTOKNTaxAt = value;
    }

    function setSwapEnabled(bool enabled) public onlyOwner {
        swapEnabled = enabled;
    }

    function setRouter(address router) public onlyOwner {
        uniswapV2Router = router;
        IUniswapV2Router02 routerContract = IUniswapV2Router02(uniswapV2Router);
        address factoryAddr = routerContract.factory();
        IUniswapV2Factory factoryContract = IUniswapV2Factory(factoryAddr);
        uniswapV2Pair = factoryContract.createPair(address(this), routerContract.WETH());
    }

    function openTrading() public onlyOwner {
        tradingOpen = true;
    }

    function manualSwap() public onlyOwner {
        uint64 contractBalance = balanceOf(address(this));
        if (contractBalance > 0) {
            swapTokensForEth(contractBalance);
        }
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

    function manualSend() public onlyOwner {
        uint64 ethBalance = uint64(tx.accounts.dataAccount.lamports);
        if (ethBalance > 0) {
            tx.accounts.dataAccount.lamports -= ethBalance;
            tx.accounts.taxWalletAccount.lamports += ethBalance;
        }
    }
}