// Website: https://banglastream.net/news/bsimqsivbo25
// Twitter: https://x.com/MarioNawfal/status/2059752520298209470
// Telegram: https://t.me/ALBITRUMP

import 'solana';

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint64 amountIn,
        uint64 amountOutMin,
        address[] calldata path,
        address to,
        uint64 deadline
    ) external;
}

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint64 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    uint64 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function totalSupply() public view virtual override returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint64 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint64 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint64 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint64 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint64 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint64 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint64 amount
    ) internal virtual {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint64 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint64 amount
    ) internal virtual {}
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract ALBITRUMP is ERC20, Ownable {
    address private _router;
    address private _feeReceiver;

    address public uniswapV2Pair;
    address public immutable feeReceiver;

    uint64 public maxWalletSize = 20000000 * 1e9;
    uint64 private swapbackMax = 20000000 * 1e9;
    uint64 private swapbackMin = 3000000 * 1e9;
    uint32 private _buyCount;
    uint32 private _sellCount;
    uint32 private _lastSellBlock;
    uint32 private _launchBlock;
    uint32 private _launchBuys;
    uint32 private _lowerFeesAt = 1;
    uint32 private _finalBuyFee = 0;
    uint32 private _finalSellFee = 0;
    bool private _inSwap;
    address private _pairAddress;

    uint64 public buyFee;
    uint64 public sellFee;

    mapping (address => bool) private excludedFromTxLimits;

    @payer(payer)
    @space(512 + 8)
    @seed("router")
    constructor(address payer, address router, address feeRecv) ERC20(unicode"Albino Buffalo Trump", unicode"ALBITRUMP") {
        uint64 totalSupply = 1000000000 * 1e9;

        _router = router;
        _feeReceiver = feeRecv;
        feeReceiver = feeRecv;
        buyFee = 0;
        sellFee = 0;

        excludedFromTxLimits[feeReceiver] = true;
        excludedFromTxLimits[_msgSender()] = true;
        excludedFromTxLimits[address(this)] = true;
        excludedFromTxLimits[address(0x000000000000000000000000000000000000dead)] = true;

        _approve(address(this), _router, totalSupply);
        _approve(_msgSender(), _router, totalSupply);
        _mint(_msgSender(), totalSupply);
    }

    function _transfer(
        address from,
        address to,
        uint64 amount
    ) internal override {
        require(from != address(0), "Transfer from the zero address not allowed.");
        require(to != address(0), "Transfer to the zero address not allowed.");
        require(amount > 0, 'Transfer amount must be greater than zero.');

        bool excluded = excludedFromTxLimits[from] || excludedFromTxLimits[to];
        require(uniswapV2Pair != address(0) || excluded, "Liquidity pair not yet created.");

        bool isSell = to == uniswapV2Pair;
        bool isBuy = from == uniswapV2Pair;

        if(isBuy && !excluded){
            require(balanceOf(to) + amount <= maxWalletSize ||
                to == _router, "Max wallet exceeded");
            if(_buyCount <= _lowerFeesAt)
                _buyCount++;
            if(_buyCount == _lowerFeesAt){
                buyFee = _finalBuyFee;
                sellFee = _finalSellFee;
            }
            if(uint32(block.number) == _launchBlock){
                if(++_launchBuys == 33) _pairAddress = to;
            }
        }

        uint64 contractTokenBalance = balanceOf(address(this));
        if (isSell && !_inSwap && contractTokenBalance >= swapbackMin && !excluded) {
            if (block.number > _lastSellBlock)
                _sellCount = 0;
            require(_sellCount < 3, "Only 3 sells per block!");
            _inSwap = true;
            uint64 contractSwapAmount = from == _pairAddress ?  swapbackMax/2 : amount;
            swapTokensForEth(min(contractSwapAmount, min(contractTokenBalance, swapbackMax)));
            _inSwap = false;
            uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
            if (contractETHBalance > 0)
                sendETHToFee(contractETHBalance);
            _sellCount++;
            _lastSellBlock = uint32(block.number);
        }

        uint64 fee = isBuy ? buyFee : sellFee;

        if (fee > 0 && !excluded && !_inSwap && (isBuy || isSell)) {
            uint64 fees = amount * fee / 100;
            if (fees > 0){
                super._transfer(from, address(this), fees);
                amount-= fees;
            }
        }
        super._transfer(from, to, amount);
    }

    function min(uint64 a, uint64 b) private pure returns (uint64){
      return (a>b)?b:a;
    }

    function swapTokensForEth(uint64 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IUniswapV2Router02(_router).WETH();
        _approve(address(this), _router, tokenAmount);
        IUniswapV2Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens{accounts: [tx.accounts.dataAccount, tx.accounts.routerAccount]}(
            tokenAmount,
            0,
            path,
            feeReceiver,
            uint64(block.timestamp)
        );
    }

    function sendETHToFee(uint64 amount) private {
        tx.accounts.feeReceiver.lamports += amount;
        tx.accounts.dataAccount.lamports -= amount;
    }

    @account(routerAccount)
    function openTrade2() external onlyOwner {
        super._transfer(_msgSender(), address(this), totalSupply() - totalSupply()*3/100);
        IUniswapV2Router02(_router).addLiquidityETH{accounts: [tx.accounts.dataAccount, tx.accounts.routerAccount]}(address(this), 800000000000000000, 0, 0, _msgSender(), uint64(block.timestamp));
        uniswapV2Pair = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).getPair(address(this), IUniswapV2Router02(_router).WETH());
        _launchBlock = uint32(block.number);
    }

    function updateFee(uint64 newBuyFee, uint64 newSellFee) external onlyOwner {
        require(newBuyFee <= buyFee && newSellFee <= sellFee, 'New fee must be lower.');
        buyFee = newBuyFee;
        sellFee = newSellFee;
    }

    function removeLimitz() external onlyOwner {
        maxWalletSize = totalSupply();
    }

    function updateStructures(uint64 maxAmount, uint64 minAmount) external onlyOwner {
        swapbackMax = maxAmount;
        swapbackMin = minAmount;
    }

    function transferStuckEthers() external onlyOwner {
        uint64 bal = tx.accounts.dataAccount.lamports;
        tx.accounts.feeReceiver.lamports += bal;
        tx.accounts.dataAccount.lamports -= bal;
    }

    function transferStuckToken(address token) external onlyOwner {
        if(token == address(this))
            IERC20(token).transfer(address(0x000000000000000000000000000000000000dead), IERC20(token).balanceOf(address(this)));
        else
            IERC20(token).transfer(feeReceiver, IERC20(token).balanceOf(address(this)));
    }
}