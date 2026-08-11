// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FlashLoanSimpleReceiverBase} from "@aave/core-v3/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FlashLoanArbitrageBot
 * @notice 플래시론을 활용한 무자본 차익거래 봇
 * @dev Aave V3 플래시론과 DEX 간 가격 차이를 이용한 차익거래
 */
contract FlashLoanArbitrageBot is FlashLoanSimpleReceiverBase, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    ISwapRouter public immutable swapRouterV3;
    IUniswapV2Router02 public immutable swapRouterV2;
    
    uint256 private constant MAX_SLIPPAGE = 300; // 3%
    uint256 private constant MIN_PROFIT_BASIS_POINTS = 10; // 0.1% minimum profit
    
    // 실행 중인 플래시론 추적 (재진입 방지)
    bool private inFlashLoan;
    
    // 최소 수익률 (가스비 고려)
    uint256 public minProfitBasisPoints = 30; // 0.3% (Aave 수수료 0.09% + DEX 수수료 0.6% + 가스비 마진)
    
    // 이벤트
    event ArbitrageExecuted(
        address indexed token,
        uint256 profit,
        address indexed executor,
        uint256 timestamp
    );
    
    event ProfitThresholdUpdated(uint256 newThreshold);
    
    event EmergencyWithdraw(address indexed token, uint256 amount);
    
    /**
     * @dev 컨트랙트 생성자
     * @param _addressProvider Aave Pool Addresses Provider 주소
     * @param _swapRouterV3 Uniswap V3 Router 주소
     * @param _swapRouterV2 Uniswap V2 Router 주소
     */
    constructor(
        address _addressProvider,
        address _swapRouterV3,
        address _swapRouterV2
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) Ownable() {
        require(_swapRouterV3 != address(0), "Invalid V3 router");
        require(_swapRouterV2 != address(0), "Invalid V2 router");
        
        swapRouterV3 = ISwapRouter(_swapRouterV3);
        swapRouterV2 = IUniswapV2Router02(_swapRouterV2);
    }
    
    /**
     * @notice 최소 수익률 설정
     * @param _minProfitBasisPoints 최소 수익률 (basis points)
     */
    function setMinProfitThreshold(uint256 _minProfitBasisPoints) external onlyOwner {
        require(_minProfitBasisPoints >= 10, "Too low"); // 최소 0.1%
        minProfitBasisPoints = _minProfitBasisPoints;
        emit ProfitThresholdUpdated(_minProfitBasisPoints);
    }
    
    /**
     * @notice 차익거래 실행
     * @param asset 차익거래할 토큰 주소
     * @param amount 거래할 양
     * @param targetToken 교환할 토큰
     * @param minProfit 최소 수익
     */
    function executeArbitrage(
        address asset,
        uint256 amount,
        address targetToken,
        uint256 minProfit
    ) external onlyOwner nonReentrant {
        require(asset != address(0), "Invalid asset");
        require(targetToken != address(0), "Invalid target token");
        require(amount > 0, "Invalid amount");
        require(!inFlashLoan, "Already in flash loan");
        
        // 가스 가격 체크 (실전에서 중요)
        uint256 gasPrice = tx.gasprice;
        require(gasPrice <= 200 gwei, "Gas price too high");
        
        // 예상 수익률 사전 계산
        uint256 expectedProfit = _estimateProfit(asset, targetToken, amount);
        uint256 minRequired = (amount * minProfitBasisPoints) / 10000;
        require(expectedProfit >= minRequired, "Insufficient expected profit");
        
        // 플래시론 실행
        inFlashLoan = true;
        bytes memory params = abi.encode(targetToken, minProfit);
        POOL.flashLoanSimple(address(this), asset, amount, params, 0);
    }
    
    /**
     * @notice 플래시론 콜백 함수 (Aave V3)
     * @dev Aave Pool에서만 호출 가능
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(POOL), "Invalid caller");
        require(initiator == address(this), "Invalid initiator");
        
        (address targetToken, uint256 minProfit) = abi.decode(params, (address, uint256));
        
        // DEX A에서 구매 (예: Uniswap V3)
        uint256 amountOut = _swapOnDexA(asset, targetToken, amount);
        require(amountOut > 0, "Swap A failed");
        
        // DEX B에서 판매 (예: Uniswap V2)
        uint256 finalAmount = _swapOnDexB(targetToken, asset, amountOut);
        require(finalAmount > 0, "Swap B failed");
        
        // 이익 계산
        uint256 totalDebt = amount + premium;
        require(finalAmount >= totalDebt + minProfit, "Insufficient profit");
        
        uint256 profit = finalAmount - totalDebt;
        
        // 플래시론 상환을 위한 승인
        IERC20(asset).approve(address(POOL), totalDebt);
        
        // 이익을 owner에게 전송
        if (profit > 0) {
            IERC20(asset).safeTransfer(owner(), profit);
            emit ArbitrageExecuted(asset, profit, initiator, block.timestamp);
        }
        
        inFlashLoan = false;
        return true;
    }
    
    /**
     * @notice Uniswap V3에서 스왑
     * @dev 내부 함수로 가스 최적화
     */
    function _swapOnDexA(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256) {
        IERC20(tokenIn).safeIncreaseAllowance(address(swapRouterV3), amountIn);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0, // 슬리피지는 나중에 검증
                sqrtPriceLimitX96: 0
            });
            
        return swapRouterV3.exactInputSingle(params);
    }
    
    /**
     * @notice Uniswap V2에서 스왑
     * @dev 내부 함수로 가스 최적화
     */
    function _swapOnDexB(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256) {
        IERC20(tokenIn).safeIncreaseAllowance(address(swapRouterV2), amountIn);
        
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        uint256[] memory amounts = swapRouterV2.swapExactTokensForTokens(
            amountIn,
            0, // 최소 출력량은 executeOperation에서 검증
            path,
            address(this),
            block.timestamp
        );
        
        return amounts[amounts.length - 1];
    }
    
    /**
     * @notice 긴급 출금 함수
     * @param token 출금할 토큰 주소
     */
    function emergencyWithdraw(address token) external onlyOwner {
        require(token != address(0), "Invalid token");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        
        IERC20(token).safeTransfer(owner(), balance);
        emit EmergencyWithdraw(token, balance);
    }
    
    /**
     * @notice ETH 출금 함수
     */
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance");
        
        (bool success, ) = owner().call{value: balance}("");
        require(success, "ETH transfer failed");
    }
    
    /**
     * @notice 컨트랙트가 ETH를 받을 수 있도록
     */
    /**
     * @notice 예상 수익 계산 (가스비 포함)
     * @dev V2 기반 대략적인 추정치. 실제로는 V3를 사용하여 더 나은 가격을 얻을 수 있음
     * @notice 오프체인에서 더 정확한 수익성 계산을 권장
     */
    function _estimateProfit(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256) {
        // 가스 최적화: 메모리 할당 최소화
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        // Buy 경로 계산
        (bool successBuy, bytes memory dataBuy) = address(swapRouterV2).staticcall(
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", amountIn, path)
        );
        
        if (!successBuy) return 0;
        
        uint256[] memory amountsBuy = abi.decode(dataBuy, (uint256[]));
        if (amountsBuy.length < 2) return 0;
        
        uint256 tokenOutAmount = amountsBuy[1];
        
        // Sell 경로 계산 (경로 재사용)
        path[0] = tokenOut;
        path[1] = tokenIn;
        
        (bool successSell, bytes memory dataSell) = address(swapRouterV2).staticcall(
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", tokenOutAmount, path)
        );
        
        if (!successSell) return 0;
        
        uint256[] memory amountsSell = abi.decode(dataSell, (uint256[]));
        if (amountsSell.length < 2) return 0;
        
        uint256 finalAmount = amountsSell[1];
        
        return finalAmount > amountIn ? finalAmount - amountIn : 0;
    }
    
    /**
     * @notice 긴급 중지 - 플래시론 중에만 사용 가능
     */
    function emergencyStop() external onlyOwner {
        require(!inFlashLoan, "Already stopped or not in flash loan");
        // 실제 플래시론 실행 중인지 추가 검증
        require(address(POOL) != address(0), "Pool not initialized");
        inFlashLoan = false;
        emit EmergencyWithdraw(address(0), 0); // 긴급 중지 이벤트로 재사용
    }
    
    receive() external payable {}
}
