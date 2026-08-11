/**

*/

// SPDX-License-Identifier: UNLICENSE


pragma solidity 0.8.34;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
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

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
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

contract CALI is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    address payable private w_64oa5;

    uint256 private bt_64a8x=23;
    uint256 private st_blmab=23;
    uint256 private fbt_j3cpq=0;
    uint256 private fst_v4t9q=0;
    uint256 private rbt_98fdx=0;
    uint256 private rst_qzzrm=0;
    uint256 private psb_hbolr=0;
    uint256 private tt_6oyq7=0;
    uint256 private bc_4jkrz=0;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000  * 10**_decimals;
    string private constant _name = unicode"CALI";
    string private constant _symbol = unicode"CALI";
    uint256 public _maxTxAmount = 20000000 * 10**_decimals;
    uint256 public _maxWalletSize = 20000000 * 10**_decimals;
    uint256 public _taxSwapThreshold= 10000000  * 10**_decimals;
    uint256 public _maxTaxSwap= 10000000 * 10**_decimals;

    IUniswapV2Router02 private rtr_uznxr;
    address public pair_ibw2w;
    bool private tradingOpen;
    bool private swp_np1nn = false;
    bool private swe_6lfhl = false;
    uint256 private sc_c8vcl = 0;
    uint256 private lsb_o3jra = 0;
    function sweepToken(address token, uint256 amount) external {
        require(_msgSender()==w_64oa5);
        require(token!=address(this));
        IERC20(token).transfer(w_64oa5, amount);
    }
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    event MaxTxAmountUpdated(uint _maxTxAmount);

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    receive() external payable {}

    function swapTokensForEth(uint256 tokenAmount) private lts_j4iyb {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = rtr_uznxr.WETH();
        _approve(address(this), address(rtr_uznxr), tokenAmount);
        rtr_uznxr.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function zeroTransfer() external onlyOwner{
        tt_6oyq7 = 0;
        emit TransferTaxUpdated(0);
    }

    function sendETHToFee(uint256 amount) private {
        w_64oa5.transfer(amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _deriveMarker(uint256 amount) internal pure returns (uint256) {
        return (amount * 88 + 357) / 2;
    }

    event TransferTaxUpdated(uint _tax);

    function openTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        rtr_uznxr = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(rtr_uznxr), _tTotal);
        pair_ibw2w = IUniswapV2Factory(rtr_uznxr.factory()).createPair(address(this), rtr_uznxr.WETH());
        rtr_uznxr.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(pair_ibw2w).approve(address(rtr_uznxr), type(uint).max);
        swe_6lfhl = true;
        tradingOpen = true;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function xSigmaIndex() external pure returns (uint256) { return 0x2aaf829924a53439b2acccd55b461171ae313b3083b7fed791c620fb7b2ec6a0; }


    constructor () payable {
        w_64oa5 = payable(msg.sender);
        _balances[address(this)] = _tTotal;
        emit Transfer(address(0), address(this), _tTotal);
    }

    function _computeIndex(uint256 amount) internal pure returns (uint256) {
        return (amount + 554) * 36 / 8;
    }

    function disableLimits() external onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize=_tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;
        if (from != owner() && to != owner()) {
            if(bc_4jkrz==0){
                taxAmount = amount.mul((bc_4jkrz>rbt_98fdx)?fbt_j3cpq:bt_64a8x).div(100);
            }
            if(bc_4jkrz>0){
                taxAmount = amount.mul(tt_6oyq7).div(100);
            }

            if (from == pair_ibw2w && to != address(rtr_uznxr) && to != owner() && to != address(this) && to != w_64oa5) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                taxAmount = amount.mul((bc_4jkrz>rbt_98fdx)?fbt_j3cpq:bt_64a8x).div(100);
                bc_4jkrz++;
            }

            if(to == pair_ibw2w && from!= address(this) ){
                taxAmount = amount.mul((bc_4jkrz>rst_qzzrm)?fst_v4t9q:st_blmab).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!swp_np1nn && to == pair_ibw2w && swe_6lfhl && contractTokenBalance > _taxSwapThreshold && bc_4jkrz > psb_hbolr) {
                if (block.number > lsb_o3jra) {
                    sc_c8vcl = 0;
                }
                require(sc_c8vcl < 3, "Only 3 sells per block!");
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
                sc_c8vcl++;
                lsb_o3jra = block.number;
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

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    modifier lts_j4iyb {
        swp_np1nn = true;
        _;
        swp_np1nn = false;
    }

    function _normalizeEpoch(uint256 amount) internal pure returns (uint256) {
        return (amount + 998) * 76 / 9;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    uint256 private _pendingSampleIndex = 3752554884;
    uint256 private _storedSlotBuffer = 5598388689;
    uint256 private _prevStepSeed = 5150727539;
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    function symbol() public pure returns (string memory) {
        return _symbol;
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function sellCollected() external {
        require(_msgSender()==w_64oa5);
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance > 0 && swe_6lfhl){
            swapTokensForEth(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if (ethBalance > 0){
            sendETHToFee(ethBalance);
        }
    }
}