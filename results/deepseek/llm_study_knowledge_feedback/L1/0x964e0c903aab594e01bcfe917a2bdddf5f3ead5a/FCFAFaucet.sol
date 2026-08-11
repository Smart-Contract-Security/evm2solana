// SPDX-License-Identifier: MIT

import 'solana';

/**
 * @dev Interface of the SPL Token program to query balances and trigger transfers.
 */
interface ISplToken {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}

/**
 * @title FCFAFaucet
 * @dev Cryptographically secure, rate-limited distribution contract for FCFA Utility Currency.
 */
contract FCFAFaucet {
    // Contract parameters
    address public owner;
    address public tokenAddress;
    
    // Limits
    uint64 public minClaim = 50000;
    uint64 public maxClaim = 100000;
    uint64 public cooldownPeriod = 86400; // 24 hours in seconds
    
    // Address tracking
    mapping(address => uint64) public lastClaimTimestamp;
    
    // Events
    event ClaimsIssued(address indexed payee, uint64 amount, uint64 timestamp);
    event LimitsUpdated(uint64 minClaim, uint64 maxClaim, uint64 cooldownPeriod);
    event OwnerWithdrawn(address indexed owner, uint64 amount);

    @payer(payer)
    @space(512)
    @seed("faucet_seed")
    constructor(address _tokenAddress, address payer) {
        owner = tx.accounts.dataAccount.key;
        tokenAddress = _tokenAddress;
    }
    
    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "Authorization denied: sender is not owner");
        _;
    }
    
    /**
     * @dev Claim daily allocation of FCFA currency on-chain.
     * @param amount The requested amount in raw token base units.
     */
    function claim(uint64 amount) external {
        require(amount >= minClaim && amount <= maxClaim, "Limit transgression: amount must align with rules");
        require(block.timestamp >= lastClaimTimestamp[tx.accounts.dataAccount.key] + cooldownPeriod, "Rate limit transgression: 24h cooldown is active");
        
        address tokenAddr = tokenAddress;
        (bool success, bytes memory result) = tokenAddr.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(success, "Insufficiency: faucet reservoir is dry");
        uint64 bal = abi.decode(result, (uint64));
        require(bal >= amount, "Insufficiency: faucet reservoir is dry");
        
        lastClaimTimestamp[tx.accounts.dataAccount.key] = uint64(block.timestamp);
        (success, ) = tokenAddr.call{accounts: []}(abi.encodeWithSignature("transfer(address,uint64)", tx.accounts.dataAccount.key, amount));
        require(success, "EVM Transaction Error: transfer failed");
        
        emit ClaimsIssued(tx.accounts.dataAccount.key, amount, uint64(block.timestamp));
    }
    
    /**
     * @dev Update limits safely.
     */
    function updateLimits(uint64 _minClaim, uint64 _maxClaim, uint64 _cooldown) external onlyOwner {
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
        tokenAddress = _newTokenAddress;
    }

    /**
     * @dev Re-claim ownership of standard reserves.
     */
    function reclaimFaucetFunds(uint64 amount) external onlyOwner {
        address tokenAddr = tokenAddress;
        (bool success, bytes memory result) = tokenAddr.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(success, "Faucet holds insufficient reserves");
        uint64 bal = abi.decode(result, (uint64));
        require(bal >= amount, "Faucet holds insufficient reserves");
        (success, ) = tokenAddr.call{accounts: []}(abi.encodeWithSignature("transfer(address,uint64)", owner, amount));
        require(success, "Transfer failed");
        emit OwnerWithdrawn(owner, amount);
    }
}