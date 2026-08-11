// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;


interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IPancakePair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IPancakeFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    function INIT_CODE_PAIR_HASH() external view returns (bytes32);
}
library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }

    function div(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
}
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}
library PancakeLibrary {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'PancakeLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'PancakeLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        pair = IPancakeFactory(factory).getPair(tokenA, tokenB);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        pairFor(factory, tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IPancakePair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'PancakeLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'PancakeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(9970);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(10000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'PancakeLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(10000);
        uint denominator = reserveOut.sub(amountOut).mul(9970);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}

abstract contract ReentrancyGuard {
    
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }
    modifier nonReentrant() {
        _nonReentrantBefore();       
        _; 
        _nonReentrantAfter();  
    }

    function _nonReentrantBefore() private {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; //     
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED; //     
    }
}

interface IWETH {
  function deposit() external payable;
  function withdraw(uint256) external;
  function approve(address, uint256) external returns (bool);
}

interface IPancakeswapV3Router {
  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }
  function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface IUniswapV3Router {
   struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}


contract ShareShip{
    using SafeMath for uint256;

    mapping(address => address) _shareShip;
    mapping(address => address[]) _shareSunList;
    mapping(address => bool) _parentIsJion;
    mapping(address => uint256) _parentRewardTimes;
    mapping(address => uint256) _parentBindTime;

    address parentAddress;
    address fund1Address;
    address fund2Address;
    constructor() {
        parentAddress = address(0x36373066F6DfdcF117b7eF84149AFe46A6A08208);
        fund1Address = address(0xD8EC5115780ab58e1313f2a94281D94AB7ca99C5);
        fund2Address = address(0x725a59690CBce210a32D3FE6e755A2f5D7917a39);
        _parentIsJion[parentAddress] = true;
    }
    
	function shareShip(address parent) public {
        require(msg.sender == tx.origin, "Only pure EOA allowed");
		require(_parentIsJion[parent] && msg.sender != parentAddress);
        _setShareShip(msg.sender,parent);
        _parentBindTime[msg.sender] = block.timestamp;
    }

    function _setShareShip(address user, address parent) internal {
        require(parent != address(0));
		require(parent != user);
        require(_shareShip[user] == address(0));
        _shareShip[user] = parent;
        _shareSunList[parent].push(user);
        _parentIsJion[user] = true;
    }

    function updateShareShip(address token, address user, address parent, uint256 amount) internal {
        if(!_parentIsJion[parent]){parent = parentAddress;}
        if(
            parent != address(0) && 
            parent != user &&
            user != parentAddress &&
            _shareShip[user] == address(0)
        ){
            _shareShip[user] = parent;
            _shareSunList[parent].push(user);
            _parentIsJion[user] = true;
            _parentBindTime[user] = block.timestamp;
        }
        reward2parent(token, user, amount);
    }
	
	function getParentIsJion(address parent) public view returns(bool){
		return _parentIsJion[parent];
	}

    function getUserParent(address user) public view returns(address){
        return _shareShip[user];
    }
	
	function getUserShareList(address user) public view returns(address[] memory){
        return _shareSunList[user];
    }

    uint256[] shareRate = [50000000,25000000,12500000,6250000,3125000,1562500,781250,0,0];
    function reward2parent(address token, address user, uint256 amount) private {
        if(token == address(0)){
            TransferHelper.safeTransferETH(fund1Address, amount.div(3));
            TransferHelper.safeTransferETH(fund2Address, amount.div(3));
        }else{
            TransferHelper.safeTransfer(token, fund1Address, amount.div(3));
            TransferHelper.safeTransfer(token, fund2Address, amount.div(3));
        }
        address parent = user;
        for(uint256 i=0;i<7;i++){
            parent = _shareShip[parent];
            if(parent == address(0)){break ;}
            _parentRewardTimes[parent] += 1;
            if(token == address(0)){
                TransferHelper.safeTransferETH(parent, amount.div(300000000).mul(shareRate[i]));
            }else{
                TransferHelper.safeTransfer(token, parent, amount.div(300000000).mul(shareRate[i]));
            }
        }
        if(token == address(0)){
            uint256 haveEthAmount = address(this).balance;
            if(haveEthAmount > 0){
                TransferHelper.safeTransferETH(parentAddress, haveEthAmount);
            }
        }else{
            uint256 haveTokenAmount = IERC20(token).balanceOf(address(this));
            if(haveTokenAmount > 0){
                TransferHelper.safeTransfer(token, parentAddress, haveTokenAmount);
            }
        }
    }

    function getUserData(address user) external view returns(address parent, uint256[] memory list){
        parent = _shareShip[user];
        list = new uint256[](10);
        list[0] = _parentRewardTimes[user];
        list[1] = _parentBindTime[user];
        list[2] = _shareSunList[user].length;
    }

    function getUserShareData(address user) external view returns(address[] memory, uint256[] memory, uint256[] memory){
        address[] memory sunlist = _shareSunList[user];
        uint256 size = sunlist.length;
        uint256[] memory timeList = new uint256[](size);
        uint256[] memory rewardsList = new uint256[](size);
        for(uint i=0;i<size;i++){
            timeList[i] = _parentBindTime[sunlist[i]];
            rewardsList[i] = _parentRewardTimes[sunlist[i]];
        }
        return (sunlist, timeList, rewardsList);
    }
}

contract UniversalSwapper is ReentrancyGuard, ShareShip {
    using SafeMath for uint256;

    address public immutable WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint256 public swapFee = 3; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    //    ģ   Ч  ת         Ѵ   
    function _transferAndSplitWithFee(
        address parent,
        address token,
        address from,
        address pair,
        uint256 totalAmount
    ) internal returns (uint256 amountInAfterFee) {
        //           
        uint256 fee = totalAmount.mul(swapFee).div(FEE_DENOMINATOR);
        amountInAfterFee = totalAmount.sub(fee);
        TransferHelper.safeTransferFrom(token, from, address(this), fee);
        TransferHelper.safeTransferFrom(token, from, pair, amountInAfterFee);

        updateShareShip(token, from, parent, fee);
        
        return amountInAfterFee;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper: TRANSFER_FAILED'
        );
    }
}


contract UniversalV2Swapper is UniversalSwapper {
    using SafeMath for uint256;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'PancakeRouter: EXPIRED');
        _;
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address userfactory, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = PancakeLibrary.sortTokens(input, output);
            IPancakePair pair = IPancakePair(PancakeLibrary.pairFor(userfactory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = PancakeLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? PancakeLibrary.pairFor(userfactory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function multipleSwapExactTokensForTokensSupportingFeeOnTransferTokens(
        address parent,
        address userfactory,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint256 amountOut){
        uint256 pathSize = path.length - 1;
        uint balanceBefore = IERC20(path[pathSize]).balanceOf(to);
        {
            address pair0 = PancakeLibrary.pairFor(userfactory, path[0], path[1]);
            _transferAndSplitWithFee(parent, path[0], msg.sender, pair0, amountIn);
        }
        _swapSupportingFeeOnTransferTokens(userfactory, path, to);
        uint balanceAfter = IERC20(path[pathSize]).balanceOf(to);
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= amountOutMin, "hd");
    }

    function multipleSwapExactETHForTokensSupportingFeeOnTransferTokens(
        address parent,
        address userfactory,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        payable
        ensure(deadline)
        returns (uint256 amountOut)
    {
        require(path[0] == WETH, 'PancakeRouter: INVALID_PATH');
        uint256 pathSize = path.length - 1;
        uint totalETH = msg.value;
        uint fee = totalETH * swapFee / FEE_DENOMINATOR;
        uint amountIn = totalETH - fee;
        IWETH(WETH).deposit{value: amountIn}();
        updateShareShip(address(0), msg.sender, parent, fee);
        uint balanceBefore = IERC20(path[pathSize]).balanceOf(to);
        address pair0 = PancakeLibrary.pairFor(userfactory, path[0], path[1]);
        _safeTransfer(WETH, pair0, amountIn);
        _swapSupportingFeeOnTransferTokens(userfactory, path, to);
        uint balanceAfter = IERC20(path[pathSize]).balanceOf(to);
        amountOut = balanceAfter - balanceBefore;
        
        require(amountOut >= amountOutMin, "hd");
    }

    function multipleSwapExactTokensForETHSupportingFeeOnTransferTokens(
        address parent,
        address userfactory,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        ensure(deadline)
        returns (uint256 amountOut)
    {
        uint256 pathSize = path.length - 1;
        require(path[pathSize] == WETH, 'PancakeRouter: INVALID_PATH');
        address pair0 = PancakeLibrary.pairFor(userfactory, path[0], path[1]);
        _transferAndSplitWithFee(parent, path[0], msg.sender, pair0, amountIn);
        _swapSupportingFeeOnTransferTokens(userfactory, path, address(this));
        amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, "hd");
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }
}

contract UniversalV3Swapper is UniversalSwapper {
  using SafeMath for uint256;

  function _firstToken(bytes memory path) internal pure returns (address token) {
    require(path.length >= 43, "path too short");
    assembly {
      token := shr(96, mload(add(path, 0x20)))
    }
  }

  function _lastToken(bytes memory path) internal pure returns (address token) {
    uint256 len = path.length;
    require(len >= 43, "path too short");
    assembly {
      token := shr(96, mload(add(add(path, 0x20), sub(len, 0x14))))
    }
  }


  //pancake
  function swapExactETHForTokens(
    address router,
    address parent,
    bytes calldata path,
    uint256 minOut,
    address to,
    uint256 deadline
  ) external payable nonReentrant returns (uint256 amountOut) {
    require(msg.value > 0, "no ETH");
    require(_firstToken(path) == WETH, "first token must be WETH");
    uint totalETH = msg.value;
    uint fee = totalETH * swapFee / FEE_DENOMINATOR;
    uint amountIn = totalETH - fee;
    IWETH(WETH).deposit{value: amountIn}();
    IWETH(WETH).approve(router,msg.value);
    updateShareShip(address(0), msg.sender, parent, fee);
    IPancakeswapV3Router.ExactInputParams memory params = IPancakeswapV3Router.ExactInputParams({
      path: path,
      recipient: to,
      deadline: deadline,
      amountIn: amountIn,
      amountOutMinimum: minOut
    });
    amountOut = IPancakeswapV3Router(router).exactInput(params);
  }
  
  function swapExactTokensForETH(
    address router,
    address parent,
    bytes calldata path,
    uint256 amountIn,
    uint256 minOut,
    address to,
    uint256 deadline
  ) external nonReentrant returns (uint256 amountOut) {
    require(amountIn > 0, "zero amount");
    require(_lastToken(path) == WETH, "last token must be WETH");

    address inToken = _firstToken(path);
    require(IERC20(inToken).transferFrom(msg.sender, address(this), amountIn), "transferFrom failed");
    uint256 fee = amountIn.mul(swapFee).div(FEE_DENOMINATOR);
    uint256 amountInAfterFee = amountIn.sub(fee);
    require(IERC20(inToken).approve(router, amountIn), "approve failed");

    // ·        WBNB  ֻ ܷ       Լ
    IPancakeswapV3Router.ExactInputParams memory params = IPancakeswapV3Router.ExactInputParams({
      path: path,
      recipient: address(this),
      deadline: deadline,
      amountIn: amountInAfterFee,
      amountOutMinimum: minOut
    });
    amountOut = IPancakeswapV3Router(router).exactInput(params);
    updateShareShip(inToken, msg.sender, parent, fee);
    //           BNB
    IWETH(WETH).withdraw(amountOut);
    (bool sent, ) = to.call{value: amountOut}("");
    require(sent, "ETH transfer failed");
  }

  function swapExactTokensForTokens(
    address router,
    address parent,
    bytes calldata path,
    uint256 amountIn,
    uint256 minOut,
    address to,
    uint256 deadline
  ) external nonReentrant returns (uint256 amountOut) {
    require(amountIn > 0, "zero amount");

    address inToken = _firstToken(path);
    require(IERC20(inToken).transferFrom(msg.sender, address(this), amountIn), "transferFrom failed");
    uint256 fee = amountIn.mul(swapFee).div(FEE_DENOMINATOR);
    uint256 amountInAfterFee = amountIn.sub(fee);
    require(IERC20(inToken).approve(router, amountIn), "approve failed");
    // ֱ       Ŀ   ַ
    IPancakeswapV3Router.ExactInputParams memory params = IPancakeswapV3Router.ExactInputParams({
      path: path,
      recipient: to,       // ? ֱ   û 
      deadline: deadline,
      amountIn: amountInAfterFee,
      amountOutMinimum: minOut
    });
    amountOut = IPancakeswapV3Router(router).exactInput(params);
    updateShareShip(inToken, msg.sender, parent, fee);
  }



    //uniswap
    function swapExactETHForTokens2Uniswap(
        address router,
        address parent,
        bytes calldata path,
        uint256 minOut,
        address to,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        require(msg.value > 0, "no ETH");
        require(deadline > 0, "deadline");
        require(_firstToken(path) == WETH, "first token must be WETH");
        uint totalETH = msg.value;
        uint fee = totalETH * swapFee / FEE_DENOMINATOR;
        uint amountIn = totalETH - fee;
        IWETH(WETH).deposit{value: amountIn}();
        IWETH(WETH).approve(router,msg.value);

        updateShareShip(address(0), msg.sender, parent, fee);
        IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router.ExactInputParams({
        path: path,
        recipient: to,
        amountIn: amountIn,
        amountOutMinimum: minOut
        });
        amountOut = IUniswapV3Router(router).exactInput(params);
    }

  
  function swapExactTokensForETH2Uniswap(
    address router,
    address parent,
    bytes calldata path,
    uint256 amountIn,
    uint256 minOut,
    address to,
    uint256 deadline
  ) external nonReentrant returns (uint256 amountOut) {
    require(amountIn > 0, "zero amount");
    require(deadline > 0, "deadline");
    require(_lastToken(path) == WETH, "last token must be WETH");

    address inToken = _firstToken(path);
    require(IERC20(inToken).transferFrom(msg.sender, address(this), amountIn), "transferFrom failed");
    uint256 fee = amountIn.mul(swapFee).div(FEE_DENOMINATOR);
    uint256 amountInAfterFee = amountIn.sub(fee);
    require(IERC20(inToken).approve(router, amountIn), "approve failed");
    IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router.ExactInputParams({
      path: path,
      recipient: address(this),
      amountIn: amountInAfterFee,
      amountOutMinimum: minOut
    });
    amountOut = IUniswapV3Router(router).exactInput(params);
    updateShareShip(inToken, msg.sender, parent, fee);
    IWETH(WETH).withdraw(amountOut);
    (bool sent, ) = to.call{value: amountOut}("");
    require(sent, "ETH transfer failed");
  }
  
  function swapExactTokensForTokens2Uniswap(
    address router,
    address parent,
    bytes calldata path,
    uint256 amountIn,
    uint256 minOut,
    address to,
    uint256 deadline
  ) external nonReentrant returns (uint256 amountOut) {
    require(amountIn > 0, "zero amount");
    require(deadline > 0, "deadline");
    address inToken = _firstToken(path);
    require(IERC20(inToken).transferFrom(msg.sender, address(this), amountIn), "transferFrom failed");
    uint256 fee = amountIn.mul(swapFee).div(FEE_DENOMINATOR);
    uint256 amountInAfterFee = amountIn.sub(fee);
    require(IERC20(inToken).approve(router, amountIn), "approve failed");
    // ֱ       Ŀ   ַ
    IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router.ExactInputParams({
      path: path,
      recipient: to,
      amountIn: amountInAfterFee,
      amountOutMinimum: minOut
    });
    amountOut = IUniswapV3Router(router).exactInput(params);
    updateShareShip(inToken, msg.sender, parent, fee);
  }
}

//0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0009c455d398326f99059ff775485246999027b3197955
contract ASSSUniversal is UniversalV2Swapper, UniversalV3Swapper {
    receive() external payable {}
}