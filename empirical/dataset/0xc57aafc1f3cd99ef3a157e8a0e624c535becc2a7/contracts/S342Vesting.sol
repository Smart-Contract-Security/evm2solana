// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract S342Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint256 public immutable startTime;
    uint256 public immutable cliffDuration;
    uint256 public immutable vestingDuration;
    uint256 public immutable totalAmount;
    uint256 public releasedAmount;

    bool private _isInitialized;
    bool private _isRevoked;

    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 unreleasedAmount);

    constructor(
        address _token,
        address _beneficiary,
        uint256 _startTime,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _totalAmount
    ) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        require(_beneficiary != address(0), "Invalid beneficiary address");
        require(_vestingDuration > _cliffDuration, "Vesting duration must be greater than cliff");
        require(_totalAmount > 0, "Total amount must be greater than 0");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        startTime = _startTime;
        cliffDuration = _cliffDuration;
        vestingDuration = _vestingDuration;
        totalAmount = _totalAmount;
    }

    // Çözüm 1: Kritik allowance kontrolü + SafeERC20 + initialize fonksiyonu
    function initialize() external onlyOwner {
        require(!_isInitialized, "Already initialized");
        
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= totalAmount, "Insufficient allowance. Please approve more tokens.");
        
        token.safeTransferFrom(msg.sender, address(this), totalAmount);
        _isInitialized = true;
    }

    // Çözüm 2: SafeERC20 + ReentrancyGuard ile güvenli release
    function release() public nonReentrant {
        require(_isInitialized, "Not initialized");
        require(!_isRevoked, "Vesting revoked");
        require(block.timestamp >= startTime + cliffDuration, "Cliff not finished");
        
        uint256 vestedAmount = _vestedAmount();
        uint256 releasable = vestedAmount - releasedAmount;
        require(releasable > 0, "No tokens to release");
        
        releasedAmount = vestedAmount;
        token.safeTransfer(beneficiary, releasable);
        emit TokensReleased(beneficiary, releasable);
    }

    // Çözüm 3: Acil durum iptali (owner sadece vesting bitmeden iptal edebilir)
    function revoke() external onlyOwner {
        require(!_isRevoked, "Already revoked");
        require(block.timestamp < startTime + vestingDuration, "Vesting already completed");
        
        _isRevoked = true;
        uint256 remaining = totalAmount - releasedAmount;
        
        if (remaining > 0) {
            token.safeTransfer(owner(), remaining);
        }
        
        emit VestingRevoked(beneficiary, remaining);
    }

    // Acil durum duraklatma (opsiyonel)
    bool private _paused;
    
    modifier whenNotPaused() {
        require(!_paused, "Contract is paused");
        _;
    }
    
    function pause() external onlyOwner {
        _paused = true;
    }
    
    function unpause() external onlyOwner {
        _paused = false;
    }

    function _vestedAmount() internal view returns (uint256) {
        if (_isRevoked) return releasedAmount;
        if (block.timestamp < startTime + cliffDuration) return 0;
        if (block.timestamp >= startTime + vestingDuration) return totalAmount;
        
        uint256 vestingPassed = block.timestamp - (startTime + cliffDuration);
        uint256 totalVesting = vestingDuration - cliffDuration;
        return (totalAmount * vestingPassed) / totalVesting;
    }

    function getReleasableAmount() public view returns (uint256) {
        if (!_isInitialized || _isRevoked) return 0;
        return _vestedAmount() - releasedAmount;
    }

    function isInitialized() public view returns (bool) {
        return _isInitialized;
    }

    function isRevoked() public view returns (bool) {
        return _isRevoked;
    }
}