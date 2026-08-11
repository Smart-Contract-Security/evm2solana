/*

we do a little fuack around and find out.

Website:    https://www.fuack.live
Telegram:   https://t.me/fuackoneth
Twitter:    https://twitter.com/fuackoneth

*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.1;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IFUACKFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
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

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

interface IFUACKRouter {
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
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

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

contract FUACK is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFUACK;
    mapping(address => bool) private bots;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000 * 10 ** _decimals;
    string private constant _name = unicode"FUACK on ETH";
    string private constant _symbol = unicode"FUACK";
    uint256 public _maxWalletSize = 20000000 * 10 ** _decimals;
    uint256 public _maxTxAmount = 20000000 * 10 ** _decimals;
    uint256 public _fuackTotal = 800000000 * 10 ** _decimals;
    uint256 public _fuackThresHold = 120 * 10 ** _decimals;
    uint256 public _fuackTaxSwap = 10000000 * 10 ** _decimals;

    IFUACKRouter private fuackRouter;
    address private fuackPair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    
    address payable private _fuackWallet;

    uint256 firstBlock;

    uint256 private _initialBuyFUACKTax = 40;
    uint256 private _initialSellFUACKTax = 25;
    uint256 private _finalBuyFUACKTax = 0;
    uint256 private _finalSellFUACKTax = 0;
    uint256 private _reduceBuyFUACKTaxAt = 9;
    uint256 private _reduceSellFUACKTaxAt = 9;
    uint256 private _preventSwapFUACKBefore = 9;
    uint256 private _buyFUACKCount = 0;
    
    event MaxTxAmountUpdated(uint _maxTxAmount);
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address _wallet) {
        _fuackWallet = payable(_wallet);
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFUACK[owner()] = true;
        _isExcludedFromFUACK[_fuackWallet] = true;
        _isExcludedFromFUACK[address(this)] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (!swapEnabled || inSwap) {
            _balances[from] = _balances[from].sub(amount);
            _balances[to] = _balances[to].add(amount);
            emit Transfer(from, to, amount);
            return;
        }

        if (from != owner() && to != owner()) {
            uint256 caFUACKBalance = balanceOf(address(this));
            bool canFUACKSwap = caFUACKBalance > _fuackThresHold;

            require(!bots[from] && !bots[to]);

            if (
                from == fuackPair &&
                to != address(fuackRouter) &&
                !_isExcludedFromFUACK[to]
            ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(
                    balanceOf(to) + amount <= _maxWalletSize,
                    "Exceeds the maxWalletSize."
                );

                if (firstBlock + 3 > block.number) {
                    require(!isContract(to));
                }
                _buyFUACKCount++;
            }

            if (to != fuackPair && !_isExcludedFromFUACK[to]) {
                require(
                    balanceOf(to) + amount <= _maxWalletSize,
                    "Exceeds the maxWalletSize."
                );
            }

            if (
                swapEnabled &&
                to == fuackPair &&
                !inSwap &&
                _buyFUACKCount > _preventSwapFUACKBefore &&
                !_isExcludedFromFUACK[from] &&
                !_isExcludedFromFUACK[to]
            ) {
                if(canFUACKSwap){
                    swapTokensForEth(
                        min(amount, min(caFUACKBalance, _fuackTaxSwap))
                    );
                }

                _fuackWallet.transfer(address(this).balance);
            }
        }

        if (!_isExcludedFromFUACK[from]) {
            uint256 fuackFees = _taxFUACKTransfer(from, to, amount);

            _balances[from] = _balances[from].sub(amount);
            _balances[to] = _balances[to].add(amount.sub(fuackFees));
            emit Transfer(from, to, amount.sub(fuackFees));
            return;
        } else {
            _basicFUACKTransfer(from, to, amount);
            return;
        }
    }

    receive() external payable {}

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function initFUACKPair() external onlyOwner {
        require(!tradingOpen, "trading is already open");

        fuackRouter = IFUACKRouter(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        _approve(address(this), address(fuackRouter), _tTotal);

        fuackPair = IFUACKFactory(fuackRouter.factory()).createPair(
            address(this),
            fuackRouter.WETH()
        );
    }

    function openFUACK() external onlyOwner {
        require(!tradingOpen, "trading is already open");

        fuackRouter.addLiquidityETH{value: address(this).balance}(
            address(this),
            _fuackTotal,
            0,
            0,
            owner(),
            block.timestamp
        );

        IERC20(fuackPair).approve(address(fuackRouter), type(uint).max);

        swapEnabled = true;
        tradingOpen = true;

        firstBlock = block.number;
    }

    function removeLimits() external onlyOwner {
        _maxTxAmount = _tTotal;
        _maxWalletSize = _tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function addBots(address[] memory bots_) public onlyOwner {
        for (uint i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }

    function delBots(address[] memory notbot) public onlyOwner {
        for (uint i = 0; i < notbot.length; i++) {
            bots[notbot[i]] = false;
        }
    }

    function isBot(address a) public view returns (bool) {
        return bots[a];
    }

    function _basicFUACKTransfer(address from, address to, uint256 amount) internal {
        unchecked {
            _balances[from] = _balances[from] - amount;
            _balances[to] = _balances[to] + amount;
        }
        emit Transfer(from, to, amount);
    }

    function _taxFUACKTransfer(address from, address to, uint256 amount) internal returns(uint256) {
        uint256 fuackFees = 0;

        fuackFees = amount
            .mul((_buyFUACKCount > _reduceBuyFUACKTaxAt) ? _finalBuyFUACKTax : _initialBuyFUACKTax)
            .div(100);

        if (to == fuackPair && from != address(this)) {
            fuackFees = amount
                .mul(
                    (_buyFUACKCount > _reduceSellFUACKTaxAt)
                        ? _finalSellFUACKTax
                        : _initialSellFUACKTax
                )
                .div(100);
        }

        if (fuackFees > 0) {
            _balances[address(this)] = _balances[address(this)].add(fuackFees);
            emit Transfer(from, address(this), fuackFees);
        }

        return fuackFees;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = fuackRouter.WETH();
        _approve(address(this), address(fuackRouter), tokenAmount);
        fuackRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
}