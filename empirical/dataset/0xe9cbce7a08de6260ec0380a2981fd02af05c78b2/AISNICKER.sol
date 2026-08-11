// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
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
        require(_owner == _msgSender(), "Ownable caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

contract AISNICKER  is Context, IERC20, Ownable {
    string public constant name = "AISNICKER";
    string public constant symbol = "AISNICKER";
    uint8 public constant decimals = 18;

    uint256 public tTotal;
    mapping(address => mapping(address => uint256)) public allowed;
    mapping(address => uint256) public balances;
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
	bool private tradingOpen;
	bool private swapEnabled = false;
	
    event OwnershipRenounced(address indexed previousOwner);
	
    constructor() {
        initiateSupply(1000000000);
        emit Transfer(address(0), msg.sender, tTotal);
    }

    function totalSupply() public view override returns (uint256) {
            return tTotal;
        }

    function initiateSupply(uint256 initialUnits) private {
        tTotal = initialUnits * 10 ** uint256(decimals);
        balances[msg.sender] = tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(recipient != address(0), "");
        require(amount <= balances[msg.sender], "");
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(msg.sender != address(0), "ERC20 approve from the zero address");
        require(spender != address(0), "ERC20 approve to the zero address");
        allowed[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function _approve(address _owner, address _spender, uint256 _value) private {
        require(_owner != address(0), "ERC20 approve from the zero address");
        require(_spender != address(0), "ERC20 approve to the zero address");
        allowed[_owner][_spender] = _value;
        emit Approval(_owner, _spender, _value);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(recipient != address(0), "");
        require(amount <= balances[sender], "");
        require(amount <= allowed[sender][msg.sender], "");
        balances[sender] -= amount;
        balances[recipient] += amount;
        allowed[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }
	
	function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowed[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "");
        allowed[msg.sender][_spender] -= _subtractedValue;
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }
	
	function allowance(address owner, address spender) public view override returns (uint256) {
        return allowed[owner][spender];
    }
	
	function openTrading() external onlyOwner() {
        require(!tradingOpen, "trading is already open");
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), totalSupply());
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        swapEnabled = true;
        tradingOpen = true;
    }

    receive() external payable {}
}