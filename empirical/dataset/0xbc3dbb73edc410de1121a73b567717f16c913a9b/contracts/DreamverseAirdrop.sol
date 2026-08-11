pragma solidity ^0.8.24;

import "openzeppelin-contracts/access/AccessControl.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/math/SafeMath.sol";
import "./VerifySignature.sol";

contract DreamverseAirdrop is AccessControl, ReentrancyGuard, VerifySignature{
    using SafeMath for uint256;
    bytes32 public constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    string private constant MESSAGE = "Dreamverse_Airdrop";
    uint256 public TOTAL_CLAIM = 12;
    uint256 public constant CLAIM_INTERVAL = 30 days;

    constructor(address _execute, address _token) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXECUTE_ROLE, _execute);
        token = IERC20(_token);
    }
    mapping(uint256 => bool) private submitted;
    IERC20 private token;
    event AirdropClaimed(address _user, uint256 _amount);
    event RewardSubmitted(address _user, uint256 _amount);
    mapping(address => AirdropInfo) public reward;
    struct AirdropInfo {
        uint256 lastClaimTime;
        uint256 amount;
        uint256 amountClaimEach;
    }

    function submitReward(
        uint256 _id,
        address _to,
        uint256 _amount,
        bytes memory signature
    ) external nonReentrant{
        require(hasRole(EXECUTE_ROLE, verify(_id, _to, _amount, MESSAGE, signature)), "Signer does not have EXECUTE_ROLE");
        require(!submitted[_id], "Request already submitted");
        require(reward[_to].amountClaimEach == 0, "User already register airdrop");
        require(msg.sender == _to, "Sender must be equal to recipient");
        AirdropInfo memory airdrop;
        airdrop.amount = _amount;
        airdrop.amountClaimEach = _amount.div(TOTAL_CLAIM);
        reward[_to] = airdrop;
        submitted[_id] = true;
        emit RewardSubmitted(_to, _amount);
    }

    function claim() external nonReentrant {
        require(reward[msg.sender].amount > 0, "Reward not existed");
        require(
            reward[msg.sender].lastClaimTime == 0 ||
            block.timestamp >= reward[msg.sender].lastClaimTime.add(CLAIM_INTERVAL),
            "Claim interval not passed");
        uint256 amountClaim;
        if (reward[msg.sender].lastClaimTime == 0) {
            amountClaim = reward[msg.sender].amountClaimEach;
            uint256 remainder = reward[msg.sender].amount.mod(TOTAL_CLAIM);
            if (remainder != 0) {
                amountClaim += remainder;
            }
        } else if (reward[msg.sender].amount > reward[msg.sender].amountClaimEach) {
            amountClaim = reward[msg.sender].amountClaimEach;
        } else {
            amountClaim = reward[msg.sender].amount;
        }
        require(token.balanceOf(address(this)) >= amountClaim, "Insufficient amount");
        token.transfer(msg.sender, amountClaim);
        reward[msg.sender].amount = reward[msg.sender].amount.sub(amountClaim);
        reward[msg.sender].lastClaimTime = block.timestamp;
        emit AirdropClaimed(msg.sender, amountClaim);
    }
}
