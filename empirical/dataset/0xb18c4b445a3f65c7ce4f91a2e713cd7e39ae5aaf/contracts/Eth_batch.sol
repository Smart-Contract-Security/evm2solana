// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleMultisend {
    // 批量转账 ETH
    function disperseEther(address payable[] calldata recipients, uint256[] calldata values) external payable {
        require(recipients.length == values.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            (bool success, ) = recipients[i].call{value: values[i]}("");
            require(success, "Transfer failed");
        }
        
        // 如果转完后有剩余的 ETH（比如用户给多了），退还给发送者
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }
}