// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract BSCCollector {
    address public owner;
    address public treasury;

    event CollectFinished(address indexed token, address indexed from, uint256 amount);
    event OwnershipTransferred(address indexed newOwner);
    event TreasuryChanged(address indexed newTreasury);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // 部署时填写收款钱包
    constructor(address _treasury) {
        owner = msg.sender;
        treasury = _treasury;
    }

    // 归集指定数量
    function collect(
        address token,
        address from,
        uint256 amount
    ) external onlyOwner returns (bool) {
        (bool success, ) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                from,
                treasury,
                amount
            )
        );
        require(success, "Collect failed");
        emit CollectFinished(token, from, amount);
        return true;
    }

    // 归集全部余额（最常用）
    function collectAll(address token, address from) external onlyOwner returns (bool) {
        (bool balSuccess, bytes memory balData) = token.call(
            abi.encodeWithSignature("balanceOf(address)", from)
        );
        require(balSuccess, "Balance check failed");
        uint256 amount = abi.decode(balData, (uint256));
        require(amount > 0, "No balance");

        (bool success, ) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                from,
                treasury,
                amount
            )
        );
        require(success, "Collect failed");
        emit CollectFinished(token, from, amount);
        return true;
    }

    // 批量归集
    function batchCollect(
        address token,
        address[] calldata accounts
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            address from = accounts[i];
            if (from == address(0)) continue;

            (bool ok, bytes memory res) = token.call(
                abi.encodeWithSignature("balanceOf(address)", from)
            );
            if (!ok) continue;

            uint256 amount = abi.decode(res, (uint256));
            if (amount == 0) continue;

            token.call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    from,
                    treasury,
                    amount
                )
            );
            emit CollectFinished(token, from, amount);
        }
    }

    // 修改收款钱包
    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Invalid address");
        treasury = _newTreasury;
        emit TreasuryChanged(_newTreasury);
    }

    // 转让所有权
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
        emit OwnershipTransferred(newOwner);
    }

    // 紧急取出误转入合约的代币
    function emergencyWithdraw(address token) external onlyOwner {
        (bool ok, bytes memory res) = token.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        if (ok) {
            uint256 bal = abi.decode(res, (uint256));
            if (bal > 0) {
                token.call(abi.encodeWithSignature("transfer(address,uint256)", treasury, bal));
            }
        }
    }
}