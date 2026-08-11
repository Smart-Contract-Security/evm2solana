// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VestingPeiro is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token;
    IERC20 public tokenUSDT;
    uint256 public vestingDuration;
    uint256 public trancheCount;
    uint256 public trancheDuration;

    struct Phase {
        uint256 dropTime;
        bool exists;
    }

    mapping(uint8 => Phase) public phases;
    mapping(uint8 => mapping(address => uint256)) public allocations;
    mapping(uint8 => mapping(address => uint256)) public allocationsUSDT;
    mapping(uint8 => mapping(address => uint256)) public claimed;
    mapping(uint8 => mapping(address => uint256)) public claimedUSDT;

    event TokenUpdated(address newToken, address tokenUSDT);
    event VestingParamsUpdated(uint256 duration, uint256 count, uint256 interval);
    event PhaseConfigured(uint8 indexed phaseId, uint256 dropTime);
    event RecipientsSet(uint8 indexed phaseId, uint256 totalRecipients);
    event Claimed(address indexed user, uint8 indexed phaseId, uint256 amount, uint256 amountUSDT);

    constructor(IERC20 _token, IERC20 _tokenUSDT) {
        token = _token;
        tokenUSDT = _tokenUSDT;
        vestingDuration = 150 days;
        trancheCount = 5;
        trancheDuration = 30 days;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setTokens(IERC20 _token, IERC20 _tokenUSDT) external onlyOwner {
        token = _token;
        tokenUSDT = _tokenUSDT;
        emit TokenUpdated(address(_token), address(_tokenUSDT));
    }

    function setVestingParams(uint256 _duration, uint256 _count, uint256 _interval) external onlyOwner {
        require(_duration >= _count * _interval, "Duration too short");
        vestingDuration = _duration;
        trancheCount   = _count;
        trancheDuration = _interval;
        emit VestingParamsUpdated(_duration, _count, _interval);
    }

    function configurePhase(uint8 phaseId, uint256 dropTime) external onlyOwner {
        require(phaseId >= 1 && phaseId <= 3, "Invalid phase");
        phases[phaseId] = Phase({dropTime: dropTime, exists: true});
        emit PhaseConfigured(phaseId, dropTime);
    }

    function setRecipients(
        uint8 phaseId,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256[] calldata amountsUSDT
    ) external onlyOwner {
        require(phases[phaseId].exists, "Phase not configured");
        require(recipients.length == amounts.length,   "Length mismatch");
        require(recipients.length == amountsUSDT.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            allocations[phaseId][recipients[i]]   = amounts[i];
            allocationsUSDT[phaseId][recipients[i]] = amountsUSDT[i];
        }

        emit RecipientsSet(phaseId, recipients.length);
    }

    function rescueTokens(
        IERC20 _token,
        address to,
        uint256 amount
    ) external onlyOwner whenNotPaused {
        _token.safeTransfer(to, amount);
    }

    function vestedAmount(uint8 phaseId, address user) public view returns (uint256) {
        Phase storage ph = phases[phaseId];
        uint256 alloc = allocations[phaseId][user];
        if (!ph.exists || block.timestamp < ph.dropTime) {
            return 0;
        }
        uint256 elapsed = block.timestamp - ph.dropTime;
        uint256 tranches = (elapsed / trancheDuration) + 1;
        if (tranches > trancheCount) {
            tranches = trancheCount;
        }
        return (alloc * tranches) / trancheCount;
    }

    function claimable(uint8 phaseId, address user) public view returns (uint256) {
        uint256 vested = vestedAmount(phaseId, user);
        return vested > claimed[phaseId][user] ? (vested - claimed[phaseId][user]) : 0;
    }

    function vestedAmountUSDT(uint8 phaseId, address user) public view returns (uint256) {
        Phase storage ph = phases[phaseId];
        uint256 alloc = allocationsUSDT[phaseId][user];
        if (!ph.exists || block.timestamp < ph.dropTime) {
            return 0;
        }
        uint256 elapsed = block.timestamp - ph.dropTime;
        uint256 tranches = (elapsed / trancheDuration) + 1;
        if (tranches > trancheCount) {
            tranches = trancheCount;
        }
        return (alloc * tranches) / trancheCount;
    }

    function claimableUSDT(uint8 phaseId, address user) public view returns (uint256) {
        uint256 vested = vestedAmountUSDT(phaseId, user);
        return vested > claimedUSDT[phaseId][user] ? (vested - claimedUSDT[phaseId][user]) : 0;
    }

    function claim(uint8 phaseId) external nonReentrant whenNotPaused {
        require(phases[phaseId].exists, "Phase not configured");

        uint256 amountToken = claimable(phaseId, msg.sender);
        uint256 amountUSDT  = claimableUSDT(phaseId, msg.sender);

        require(amountToken > 0 || amountUSDT > 0, "Nothing to claim");

        if (amountToken > 0) {
            claimed[phaseId][msg.sender] += amountToken;
            token.safeTransfer(msg.sender, amountToken);
        }

        if (amountUSDT > 0) {
            claimedUSDT[phaseId][msg.sender] += amountUSDT;
            tokenUSDT.safeTransfer(msg.sender, amountUSDT);
        }

        emit Claimed(msg.sender, phaseId, amountToken, amountUSDT);
    }
}
