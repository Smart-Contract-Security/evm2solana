// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract wTAOLightningBridge is Ownable {
    ERC20 public wtaoToken;
    address public bridgeWallet;
    uint256 public minBridgeAmount = 5e7; // 0.05 wTAO

    event TokensBridged(uint256 amount, string withdrawSS58, address indexed from, address indexed bridgeWallet);

    constructor(address _wtaoTokenAddress, address _bridgeWallet) Ownable(msg.sender) {
        wtaoToken = ERC20(_wtaoTokenAddress);
        bridgeWallet = _bridgeWallet;
    }
    
    function bridge(uint256 _amount, string memory _withdrawSS58) external {    
        require(_amount >= minBridgeAmount, "Amount must be at least minBridgeAmount");        
        require(wtaoToken.transferFrom(msg.sender, bridgeWallet, _amount), "Bridge deposit failed");
        
        emit TokensBridged(_amount, _withdrawSS58, msg.sender, bridgeWallet);
    }

    function setBridgeWallet(address _newBridgeWallet) external onlyOwner {
        bridgeWallet = _newBridgeWallet;
    }

    function setMinBridgeAmount(uint256 _newMinBridgeAmount) external onlyOwner {
        minBridgeAmount = _newMinBridgeAmount;
    }
}
