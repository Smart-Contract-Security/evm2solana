// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title USDC Permit Executor
 * @dev 基于 USDC Permit 的合约归集系统 - Executor 合约
 *
 * 架构说明：
 * - 用户授权给本合约（spender）而非普通钱包
 * - Owner 控制合约执行 permit 和 collect
 * - Collector 地址由后端传入，动态可配置
 * - Spender 固定为 address(this)，防止安全风险
 */

// ✅ Interface 必须定义在 contract 外部
interface IUSDC {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract USDCPermitExecutor is Ownable {
    using SafeERC20 for IERC20;

    // USDC 合约地址（以太坊主网）
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // 事件日志
    event PermitExecuted(address indexed user, uint256 value, uint256 deadline);
    event Collected(address indexed from, address indexed to, uint256 amount);

    constructor(address _initialOwner) Ownable(_initialOwner) {
        // 不需要设置 defaultCollector，由后端传入
    }

    /**
     * @dev 执行 USDC Permit 上链
     * @notice spender 固定为 address(this)，不允许外部传入，防止安全风险
     * @param owner 用户地址
     * @param value 授权金额
     * @param deadline 过期时间
     * @param v 签名 v 值
     * @param r 签名 r 值
     * @param s 签名 s 值
     */
    function executePermit(
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyOwner {
        // ✅ 强制 spender = address(this)，确保用户只授权给 Executor 合约
        IUSDC(USDC).permit(
            owner,
            address(this),  // ← 固定为本合约地址
            value,
            deadline,
            v,
            r,
            s
        );

        emit PermitExecuted(owner, value, deadline);
    }

    /**
     * @dev 归集 USDC 到指定地址
     * @param from 用户地址
     * @param to 归集目标地址（由后端传入，从数据库读取）
     * @param amount 归集金额
     */
    function collect(
        address from,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid collector address");

        IERC20(USDC).safeTransferFrom(from, to, amount);

        emit Collected(from, to, amount);
    }

    /**
     * @dev 紧急提币功能（防止合约中残留代币）
     * @param token 代币地址
     * @param recipient 接收地址
     * @param amount 金额
     */
    function emergencyWithdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);
    }
}
