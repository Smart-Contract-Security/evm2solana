// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FeeRouter
 * @notice Routes token swaps through Uniswap V3, deducting a
 *         platform fee before sending proceeds to recipient.
 *         One transaction: swap + fee deduction + delivery.
 * @dev Security: Ownable2Step, ReentrancyGuard, Pausable
 */
contract FeeRouter is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════
    // State
    // ═══════════════════════════════════

    /// @notice Wallet receiving platform fees
    address public feeWallet;

    /// @notice Fee in basis points (100 = 1%)
    uint256 public feeBps;

    /// @notice Maximum allowed fee (10% hard cap)
    uint256 public constant MAX_FEE_BPS = 1000;

    /// @notice Uniswap V3 SwapRouter02
    address public immutable swapRouter;

    // ═══════════════════════════════════
    // Events
    // ═══════════════════════════════════

    event SwapExecuted(
        address indexed recipient,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );

    event FeeWalletUpdated(
        address indexed oldWallet,
        address indexed newWallet
    );

    event FeeBpsUpdated(
        uint256 oldFeeBps,
        uint256 newFeeBps
    );

    // ═══════════════════════════════════
    // Errors
    // ═══════════════════════════════════

    error ZeroAddress();
    error FeeTooHigh(uint256 requested, uint256 max);
    error SwapFailed();
    error InsufficientOutput(uint256 got, uint256 minimum);
    error InvalidAmount();

    // ═══════════════════════════════════
    // Constructor
    // ═══════════════════════════════════

    /**
     * @param _swapRouter Uniswap V3 SwapRouter02 address
     * @param _feeWallet  Address receiving platform fees
     * @param _feeBps     Initial fee in basis points (100 = 1%)
     */
    constructor(
        address _swapRouter,
        address _feeWallet,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_swapRouter == address(0)) revert ZeroAddress();
        if (_feeWallet == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps, MAX_FEE_BPS);

        swapRouter = _swapRouter;
        feeWallet = _feeWallet;
        feeBps = _feeBps;
    }

    // ═══════════════════════════════════
    // Core: swapExactInputSingle
    // ═══════════════════════════════════

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Execute exactInputSingle swap via Uniswap V3,
     *         deduct platform fee from output, deliver remainder
     *         to recipient — all in one transaction.
     *
     * @param params Swap parameters (tokenIn, tokenOut,
     *               fee tier, recipient, amounts)
     * @return amountOut Net amount delivered to recipient
     *                   after fee deduction
     */
    function swapExactInputSingle(
        SwapParams calldata params
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        if (params.amountIn == 0) revert InvalidAmount();
        if (params.recipient == address(0)) revert ZeroAddress();
        if (params.tokenIn == address(0)) revert ZeroAddress();
        if (params.tokenOut == address(0)) revert ZeroAddress();

        // Pull tokenIn from caller
        IERC20(params.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Approve router
        IERC20(params.tokenIn).forceApprove(swapRouter, params.amountIn);

        // Build Uniswap V3 exactInputSingle calldata
        // SwapRouter02 struct (no deadline field). The 7 fields below match
        // ExactInputSingleParams; static-tuple encoding is identical to
        // inlining each field so this produces valid calldata.
        bytes memory swapData = abi.encodeWithSelector(
            0x04e45aaf, // exactInputSingle selector
            params.tokenIn,
            params.tokenOut,
            params.fee,
            address(this), // router sends to us first
            params.amountIn,
            uint256(0), // min=0 here, we check after fee deduction
            params.sqrtPriceLimitX96
        );

        // Execute swap
        (bool success, bytes memory result) = swapRouter.call(swapData);
        if (!success) revert SwapFailed();

        uint256 rawOut = abi.decode(result, (uint256));

        // Deduct fee
        uint256 platformFee = (rawOut * feeBps) / 10000;
        uint256 netOut = rawOut - platformFee;

        // Check minimum output AFTER fee deduction
        if (netOut < params.amountOutMinimum) {
            revert InsufficientOutput(netOut, params.amountOutMinimum);
        }

        // Transfer fee to fee wallet
        if (platformFee > 0) {
            IERC20(params.tokenOut).safeTransfer(feeWallet, platformFee);
        }

        // Transfer net output to recipient
        IERC20(params.tokenOut).safeTransfer(params.recipient, netOut);

        emit SwapExecuted(
            params.recipient,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            netOut,
            platformFee
        );

        return netOut;
    }

    // ═══════════════════════════════════
    // ETH → Token swap (WETH unwrap path)
    // ═══════════════════════════════════

    /**
     * @notice Swap ETH → token via Uniswap V3 WETH path,
     *         deduct fee, deliver to recipient.
     */
    function swapETHForTokens(
        address tokenOut,
        uint24  poolFee,
        address recipient,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        address weth
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        if (msg.value == 0) revert InvalidAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (tokenOut == address(0)) revert ZeroAddress();
        if (weth == address(0)) revert ZeroAddress();

        bytes memory swapData = abi.encodeWithSelector(
            0x04e45aaf,
            weth,
            tokenOut,
            poolFee,
            address(this),
            msg.value,
            uint256(0),
            sqrtPriceLimitX96
        );

        (bool success, bytes memory result) =
            swapRouter.call{value: msg.value}(swapData);
        if (!success) revert SwapFailed();

        uint256 rawOut = abi.decode(result, (uint256));

        uint256 platformFee = (rawOut * feeBps) / 10000;
        uint256 netOut = rawOut - platformFee;

        if (netOut < amountOutMinimum) {
            revert InsufficientOutput(netOut, amountOutMinimum);
        }

        if (platformFee > 0) {
            IERC20(tokenOut).safeTransfer(feeWallet, platformFee);
        }

        IERC20(tokenOut).safeTransfer(recipient, netOut);

        emit SwapExecuted(
            recipient,
            weth,
            tokenOut,
            msg.value,
            netOut,
            platformFee
        );

        return netOut;
    }

    // ═══════════════════════════════════
    // Admin functions
    // ═══════════════════════════════════

    /**
     * @notice Update fee wallet address
     * @dev Only owner (Ownable2Step — requires acceptance)
     */
    function setFeeWallet(address _feeWallet) external onlyOwner {
        if (_feeWallet == address(0)) revert ZeroAddress();
        emit FeeWalletUpdated(feeWallet, _feeWallet);
        feeWallet = _feeWallet;
    }

    /**
     * @notice Update platform fee
     * @param _feeBps New fee in basis points (max 1000 = 10%)
     */
    function setFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps, MAX_FEE_BPS);
        emit FeeBpsUpdated(feeBps, _feeBps);
        feeBps = _feeBps;
    }

    /// @notice Pause all swaps (emergency)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause swaps
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Rescue accidentally sent tokens
     * @dev Cannot rescue tokens mid-swap (reentrancy guard)
     */
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Rescue accidentally sent ETH
    function rescueETH() external onlyOwner {
        (bool ok, ) = owner().call{value: address(this).balance}("");
        require(ok, "ETH transfer failed");
    }

    receive() external payable {}
}
