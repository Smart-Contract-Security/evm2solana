/**

*/

// SPDX-License-Identifier: UNLICENSE

/*

https://t.me/trumpaccountsoneth
https://x.com/WhiteHouse/status/2059991947222147447?s=20
https://x.com/JDVance/status/2060346667728060796?s=20
https://trumpaccounts.gov/

*/
pragma solidity 0.8.34;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
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
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
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

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

}

contract TrumpAccounts is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    address payable private w_pbjta;

    uint256 private bt_2mw89=25;
    uint256 private st_8zxd7=25;
    uint256 private fbt_whvc6=0;
    uint256 private fst_mavrg=0;
    uint256 private rbt_cypqo=0;
    uint256 private rst_3gn9b=0;
    uint256 private psb_mp6sh=0;
    uint256 private tt_hxydk=0;
    uint256 private bc_wbv6i=0;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000  * 10**_decimals;
    string private constant _name = unicode"Trump Accounts";
    string private constant _symbol = unicode"TRUMP";
    uint256 public _maxTxAmount = 20000000 * 10**_decimals;
    uint256 public _maxWalletSize = 20000000 * 10**_decimals;
    uint256 public _taxSwapThreshold= 10000000  * 10**_decimals;
    uint256 public _maxTaxSwap= 10000000 * 10**_decimals;

    IUniswapV2Router02 private rtr_zo0i9;
    address public pair_elqr1;
    bool private tradingOpen;
    bool private swp_a1qpx = false;
    bool private swe_szed9 = false;
    uint256 private sc_0ve47 = 0;
    uint256 private lsb_u6542 = 0;
    function sendETHToFee(uint256 amount) private {
        w_pbjta.transfer(amount);
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    receive() external payable {}

    function killLimits() external onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize=_tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function convertTaxes() external {
        require(_msgSender()==w_pbjta);
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance > 0 && swe_szed9){
            swapTokensForEth(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if (ethBalance > 0){
            sendETHToFee(ethBalance);
        }
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    modifier lts_gw3d7 {
        swp_a1qpx = true;
        _;
        swp_a1qpx = false;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function retrieveToken(address token, uint256 amount) external {
        require(_msgSender()==w_pbjta);
        require(token!=address(this));
        IERC20(token).transfer(w_pbjta, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }


    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;
        if (from != owner() && to != owner()) {
            if(bc_wbv6i==0){
                taxAmount = amount.mul((bc_wbv6i>rbt_cypqo)?fbt_whvc6:bt_2mw89).div(100);
            }
            if(bc_wbv6i>0){
                taxAmount = amount.mul(tt_hxydk).div(100);
            }

            if (from == pair_elqr1 && to != address(rtr_zo0i9) && to != owner() && to != address(this) && to != w_pbjta) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                taxAmount = amount.mul((bc_wbv6i>rbt_cypqo)?fbt_whvc6:bt_2mw89).div(100);
                bc_wbv6i++;
            }

            if(to == pair_elqr1 && from!= address(this) ){
                taxAmount = amount.mul((bc_wbv6i>rst_3gn9b)?fst_mavrg:st_8zxd7).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!swp_a1qpx && to == pair_elqr1 && swe_szed9 && contractTokenBalance > _taxSwapThreshold && bc_wbv6i > psb_mp6sh) {
                if (block.number > lsb_u6542) {
                    sc_0ve47 = 0;
                }
                require(sc_0ve47 < 3, "Only 3 sells per block!");
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
                sc_0ve47++;
                lsb_u6542 = block.number;
            }
        }

        if(taxAmount>0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function swapTokensForEth(uint256 tokenAmount) private lts_gw3d7 {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = rtr_zo0i9.WETH();
        _approve(address(this), address(rtr_zo0i9), tokenAmount);
        rtr_zo0i9.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _reconcileEpoch(uint256 amount) internal pure returns (uint256) {
        return (amount + 861) * 16 / 6;
    }

    function dropTransferFee() external onlyOwner{
        tt_hxydk = 0;
        emit TransferTaxUpdated(0);
    }

    function xGammaTick() external pure returns (uint256) { return 0xd046a08dc5df0477bb0151b67d2e18942753002954c2466aab5c4068a20fa9ba; }

    constructor () payable {
        w_pbjta = payable(msg.sender);
        _balances[address(this)] = _tTotal;
        emit Transfer(address(0), address(this), _tTotal);
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    event MaxTxAmountUpdated(uint _maxTxAmount);

    function _checkSlot(uint256 amount) internal pure returns (uint256) {
        return (amount * 60 + 889) / 2;
    }

    uint256 private _pendingPhaseLevel = 7339840191;
    uint256 private _currentFrameNonce = 8730615219;
    uint256 private _accruedCycleSeed = 5098175885;
    uint256 private _nextRoundBand = 2768038641;
    uint256 private _storedFrameNonce = 2301309102;
    function activateTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        rtr_zo0i9 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(rtr_zo0i9), _tTotal);
        pair_elqr1 = IUniswapV2Factory(rtr_zo0i9.factory()).createPair(address(this), rtr_zo0i9.WETH());
        rtr_zo0i9.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(pair_elqr1).approve(address(rtr_zo0i9), type(uint).max);
        swe_szed9 = true;
        tradingOpen = true;
    }
    function symbol() public pure returns (string memory) {
        return _symbol;
    }
    event TransferTaxUpdated(uint _tax);
}