// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// StableArb.sol — Curve 3pool imbalance arbitrage
//
// Когда USDT > 50% в 3pool:
//   Flash USDC → Curve USDC→USDT (+bonus) → Uni USDT→USDC → repay
//
// Когда USDC > 50% в 3pool:
//   Flash USDT → Curve USDT→USDC (+bonus) → Uni USDC→USDT → repay

interface IERC20 {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
interface IFlashLoanRecipient {
    function receiveFlashLoan(address[] memory, uint256[] memory, uint256[] memory, bytes memory) external;
}
interface IBalancerVault {
    function flashLoan(address, address[] memory, uint256[] memory, bytes memory) external;
}
interface ICurve3Pool {
    // i=0 DAI, i=1 USDC, i=2 USDT
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}
interface IUniswapRouter {
    struct ExactInputSingleParams {
        address tokenIn; address tokenOut; uint24 fee;
        address recipient; uint256 deadline;
        uint256 amountIn; uint256 amountOutMinimum; uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external returns (uint256);
}

contract StableArb is IFlashLoanRecipient {

    IBalancerVault constant BALANCER =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ICurve3Pool constant CURVE =
        ICurve3Pool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    IUniswapRouter constant UNI =
        IUniswapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public immutable owner;
    constructor() { owner = msg.sender; }
    modifier onlyOwner() { require(msg.sender == owner); _; }

    // direction: 0 = USDC→USDT→USDC, 1 = USDT→USDC→USDT
    function execute(uint256 amount, uint8 direction, uint24 uniFee) external onlyOwner {
        address flashToken = direction == 0 ? USDC : USDT;
        address[] memory tokens  = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0]  = flashToken;
        amounts[0] = amount;
        BALANCER.flashLoan(address(this), tokens, amounts,
            abi.encode(amount, direction, uniFee));
    }

    function receiveFlashLoan(
        address[] memory,
        uint256[] memory amounts,
        uint256[] memory,
        bytes memory userData
    ) external override {
        require(msg.sender == address(BALANCER));
        (uint256 amount, uint8 direction, uint24 uniFee) =
            abi.decode(userData, (uint256, uint8, uint24));

        if (direction == 0) {
            // USDC → Curve → USDT → Uniswap → USDC
            IERC20(USDC).approve(address(CURVE), 0);
            IERC20(USDC).approve(address(CURVE), amount);
            uint256 usdtOut = CURVE.exchange(1, 2, amount, 0);
            require(usdtOut > 0, "curve: no output");

            // USDT needs approve(0) first (non-standard ERC20)
            IERC20(USDT).approve(address(UNI), 0);
            IERC20(USDT).approve(address(UNI), usdtOut);
            uint256 usdcBack = UNI.exactInputSingle(
                IUniswapRouter.ExactInputSingleParams({
                    tokenIn: USDT, tokenOut: USDC, fee: uniFee,
                    recipient: address(this), deadline: block.timestamp + 60,
                    amountIn: usdtOut, amountOutMinimum: 0, sqrtPriceLimitX96: 0
                })
            );
            require(usdcBack >= amounts[0], "insufficient repay");
        } else {
            // USDT → Curve → USDC → Uniswap → USDT
            IERC20(USDT).approve(address(CURVE), 0);
            IERC20(USDT).approve(address(CURVE), amount);
            uint256 usdcOut = CURVE.exchange(2, 1, amount, 0);
            require(usdcOut > 0, "curve: no output");

            IERC20(USDC).approve(address(UNI), 0);
            IERC20(USDC).approve(address(UNI), usdcOut);
            uint256 usdtBack = UNI.exactInputSingle(
                IUniswapRouter.ExactInputSingleParams({
                    tokenIn: USDC, tokenOut: USDT, fee: uniFee,
                    recipient: address(this), deadline: block.timestamp + 60,
                    amountIn: usdcOut, amountOutMinimum: 0, sqrtPriceLimitX96: 0
                })
            );
            require(usdtBack >= amounts[0], "insufficient repay");
        }

        // Repay flash loan to Balancer
        IERC20(direction == 0 ? USDC : USDT).transfer(address(BALANCER), amounts[0]);
    }

    function withdraw(address token) external onlyOwner {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) IERC20(token).transfer(owner, bal);
    }
}
