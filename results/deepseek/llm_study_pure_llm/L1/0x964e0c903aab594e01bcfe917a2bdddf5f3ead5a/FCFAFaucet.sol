// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'solana';

/**
 * @dev Interface of the ERC20 standard token to query balances and trigger transfers.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title FCFAFaucet
 * @dev Cryptographically secure, rate-limited distribution contract for FCFA Utility Currency.
 */
contract FCFAFaucet {
    // Contract parameters
    address public owner;
    IERC20 public tokenInstance;
    
    // Limits
    uint256 public minClaim = 50000;
    uint256 public maxClaim = 100000;
    uint256 public cooldownPeriod = 24 hours;
    
    // Address tracking
    mapping(address => uint256) public lastClaimTimestamp;
    
    // Events
    event ClaimsIssued(address indexed payee, uint256 amount, uint256 timestamp);
    event LimitsUpdated(uint256 minClaim, uint256 maxClaim, uint256 cooldownPeriod);
    event OwnerWithdrawn(address indexed owner, uint256 amount);

    @payer(payer)
    constructor(address _tokenAddress) {
        owner = tx.accounts.payer.key;
        tokenInstance = IERC20(_tokenAddress);
    }
    
    modifier onlyOwner() {
        require(tx.accounts.payer.key == owner, "Authorization denied: sender is not owner");
        _;
    }
    
    /**
     * @dev Claim daily allocation of FCFA currency on-chain.
     * @param amount The requested amount in raw token base units.
     */
    function claim(uint256 amount) external {
        require(amount >= minClaim && amount <= maxClaim, "Limit transgression: amount must align with rules");
        require(block.timestamp >= lastClaimTimestamp[tx.accounts.payer.key] + cooldownPeriod, "Rate limit transgression: 24h cooldown is active");
        require(tokenInstance.balanceOf(address(this)) >= amount, "Insufficiency: faucet reservoir is dry");
        
        lastClaimTimestamp[tx.accounts.payer.key] = block.timestamp;
        require(tokenInstance.transfer(tx.accounts.payer.key, amount), "EVM Transaction Error: transfer failed");
        
        emit ClaimsIssued(tx.accounts.payer.key, amount, block.timestamp);
    }
    
    /**
     * @dev Update limits safely.
     */
    function updateLimits(uint256 _minClaim, uint256 _maxClaim, uint256 _cooldown) external onlyOwner {
        require(_minClaim <= _maxClaim, "Logic error: minClaim exceeds maxClaim");
        minClaim = _minClaim;
        maxClaim = _maxClaim;
        cooldownPeriod = _cooldown;
        emit LimitsUpdated(_minClaim, _maxClaim, _cooldown);
    }
    
    /**
     * @dev Update token smart contract address.
     */
    function setTokenAddress(address _newTokenAddress) external onlyOwner {
        require(_newTokenAddress != address(0), "Zero address provided");
        tokenInstance = IERC20(_newTokenAddress);
    }

    /**
     * @dev Re-claim ownership of standard reserves.
     */
    function reclaimFaucetFunds(uint256 amount) external onlyOwner {
        uint256 bal = tokenInstance.balanceOf(address(this));
        require(bal >= amount, "Faucet holds insufficient reserves");
        require(tokenInstance.transfer(owner, amount), "Transfer failed");
        emit OwnerWithdrawn(owner, amount);
    }
}