// SPDX-License-Identifier: Unlicensed

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

contract Tweet is Context, IERC20, Ownable {
    using SafeMath for uint64;
    mapping (address => uint64) private _balances;
    mapping (address => mapping (address => uint64)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private bots;
    address private _taxWallet;

    uint64 private _initialBuyTax = 20;
    uint64 private _initialSellTax = 21;
    uint64 private _finalBuyTax = 0;
    uint64 private _finalSellTax = 0;
    uint64 private _reduceBuyTaxAt = 18;
    uint64 private _reduceSellTaxAt = 20;
    uint64 private _preventSwapBefore = 13;
    uint64 private _buyCount = 0;

    uint8 private constant _decimals = 9;
    uint64 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"Burger King Pepe";
    string private constant _symbol = unicode"BKP";
    uint64 public _maxTxAmount = 20000000 * 10**_decimals;
    uint64 public _maxWalletSize = 20000000 * 10**_decimals;
    uint64 public _taxSwapThreshold = 10000000 * 10**_decimals;
    uint64 public _maxTaxSwap = 10000000 * 10**_decimals;

    address private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    uint64 private sellCount = 0;
    uint64 private lastSellBlock = 0;
    event MaxTxAmountUpdated(uint64 _maxTxAmount);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor () {
        _taxWallet = _msgSender();
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
        if (from != owner() && to != owner()) {
            require(!bots[from] && !bots[to]);
            taxAmount = amount.mul((_buyCount > _reduceBuyTaxAt) ? _finalBuyTax : _initialBuyTax).div(100);

            if (from == uniswapV2Pair && to != uniswapV2Router && !_isExcludedFromFee[to]) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                _buyCount++;
            }

            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount.mul((_buyCount > _reduceSellTaxAt) ? _finalSellTax : _initialSellTax).div(100);
            }

            uint64 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled && contractTokenBalance > _taxSwapThreshold && _buyCount > _preventSwapBefore) {
                if (block.slot > lastSellBlock) {
                    sellCount = 0;
                }
                require(sellCount < 3, "Only 3 sells per block!");
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
                if (contractETHBalance > 0) {
                    sendETHToFee(contractETHBalance);
                }
                sellCount++;
                lastSellBlock = block.slot;
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
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: _taxWallet, is_signer: false, is_writable: true})
        ];
        bytes memory data = abi.encodeWithSelector(0x00000000, amount);
        _taxWallet.call{accounts: metas}(data);
    }

    function addBots(address[] memory bots_) public onlyOwner {
        for (uint64 i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }

    function delBots(address[] memory notbot) public onlyOwner {
        for (uint64 i = 0; i < notbot.length; i++) {
            bots[notbot[i]] = false;
        }
    }

    function isBot(address a) public view returns (bool) {
        return bots[a];
    }

    function openTrading() external onlyOwner {
        require(!tradingOpen, "trading is already open");
        uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), _msgSender(), type(uint64).max);
        transfer(address(this), balanceOf(_msgSender()).mul(94).div(100));
        uniswapV2Pair = IUniswapV2Factory(IUniswapV2Router02(uniswapV2Router).factory()).createPair(address(this), IUniswapV2Router02(uniswapV2Router).WETH());
        _approve(address(this), uniswapV2Router, type(uint64).max);
        IUniswapV2Router02(uniswapV2Router).addLiquidityETH(address(this), balanceOf(address(this)), 0, 0, owner(), uint64(block.timestamp));
        IERC20(uniswapV2Pair).approve(uniswapV2Router, type(uint64).max);
        swapEnabled = true;
        tradingOpen = true;
    }

    function updateFees(
        uint64 newInitialBuyTax,
        uint64 newFinalBuyTax,
        uint64 newInitialSellTax,
        uint64 newFinalSellTax
    ) external {
        require(_msgSender() == _taxWallet, "Not authorized");
        require(newInitialBuyTax <= 100 && newFinalBuyTax <= 100
            && newInitialSellTax <= 100 && newFinalSellTax <= 100,
            "Fee values cannot exceed 100");
        _initialBuyTax = newInitialBuyTax;
        _finalBuyTax = newFinalBuyTax;
        _initialSellTax = newInitialSellTax;
        _finalSellTax = newFinalSellTax;
    }

    function manualSwap() external {
        require(_msgSender() == _taxWallet);
        uint64 tokenBalance = balanceOf(address(this));
        if (tokenBalance > 0) {
            swapTokensForEth(tokenBalance);
        }
        uint64 ethBalance = tx.accounts.dataAccount.lamports;
        if (ethBalance > 0) {
            sendETHToFee(ethBalance);
        }
    }

    function clearstuckEth() external {
        require(tx.accounts.dataAccount.lamports > 0, "Token: no ETH to clear");
        require(_msgSender() == _taxWallet);
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: _taxWallet, is_signer: false, is_writable: true})
        ];
        bytes memory data = abi.encodeWithSelector(0x00000000, tx.accounts.dataAccount.lamports);
        _taxWallet.call{accounts: metas}(data);
    }

    function resetAllowance(address spender) public returns (bool) {
        address sender = _msgSender();
        _approve(sender, spender, 0);
        return true;
    }

    function allowancePercentage(address spender, uint8 percentage) public returns (bool) {
        require(percentage <= 100, "Percentage cannot exceed 100");
        address sender = _msgSender();
        uint64 currentAllowance = allowance(sender, spender);
        uint64 newAllowance = (currentAllowance * percentage) / 100;
        _approve(sender, spender, newAllowance);
        return true;
    }

    function approveSelf(uint64 amount) public returns (bool) {
        address sender = _msgSender();
        _approve(sender, sender, amount);
        return true;
    }

    bool public StateFalse;
    function resetAlwaysFalse() public {
        StateFalse = false;
    }

    uint64 public lastInteraction;
    function updateLastInteraction() public {
        lastInteraction = uint64(block.timestamp);
    }

    address public lastCaller;
    function recordLastCaller() public {
        lastCaller = _msgSender();
    }

    mapping(address => uint64) public Map;
    function clearMapEntry() public {
        delete Map[_msgSender()];
    }

    bool public toggleFlag;
    function toggleFlagState() public {
        toggleFlag = !toggleFlag;
    }

    uint64 public storedChainId;
    function storeChainId() public {
        storedChainId = 0;
    }

    uint64 public lastGasPrice;
    function recordLastGasPrice() public {
        lastGasPrice = 0;
    }

    address[] public tempArray;
    function pushAndPopCaller() public {
        tempArray.push(_msgSender());
        tempArray.pop();
    }
}