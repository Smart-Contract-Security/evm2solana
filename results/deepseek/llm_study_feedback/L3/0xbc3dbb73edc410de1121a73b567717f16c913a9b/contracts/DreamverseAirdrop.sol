// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import 'solana';

contract DreamverseAirdrop {
    bytes32 public constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    string private constant MESSAGE = "Dreamverse_Airdrop";
    uint256 public TOTAL_CLAIM = 12;
    uint256 public constant CLAIM_INTERVAL = 30 days;

    address private _admin;
    address private _execute;
    address private _token;

    constructor(address execute_role, address token_addr) {
        _admin = tx.accounts[0].key;
        _execute = execute_role;
        _token = token_addr;
    }

    mapping(uint256 => bool) private submitted;
    mapping(address => AirdropInfo) public reward;

    struct AirdropInfo {
        uint256 lastClaimTime;
        uint256 amount;
        uint256 amountClaimEach;
    }

    event AirdropClaimed(address _user, uint256 _amount);
    event RewardSubmitted(address _user, uint256 _amount);

    modifier onlyRole(bytes32 role, address account) {
        if (role == EXECUTE_ROLE) {
            require(account == _execute, "Signer does not have EXECUTE_ROLE");
        } else if (role == DEFAULT_ADMIN_ROLE) {
            require(account == _admin, "Caller does not have admin role");
        }
        _;
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        if (role == EXECUTE_ROLE) {
            return account == _execute;
        } else if (role == DEFAULT_ADMIN_ROLE) {
            return account == _admin;
        }
        return false;
    }

    function verify(
        uint256 _id,
        address _to,
        uint256 _amount,
        string memory _message,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(_id, _to, _amount, _message));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) {
            v += 27;
        }
        return ecrecover(ethSignedHash, v, r, s);
    }

    function submitReward(
        uint256 _id,
        address _to,
        uint256 _amount,
        bytes memory signature
    ) external {
        address signer = verify(_id, _to, _amount, MESSAGE, signature);
        require(hasRole(EXECUTE_ROLE, signer), "Signer does not have EXECUTE_ROLE");
        require(!submitted[_id], "Request already submitted");
        require(reward[_to].amountClaimEach == 0, "User already register airdrop");
        require(tx.accounts[0].key == _to, "Sender must be equal to recipient");
        AirdropInfo memory airdrop;
        airdrop.amount = _amount;
        airdrop.amountClaimEach = _amount / TOTAL_CLAIM;
        reward[_to] = airdrop;
        submitted[_id] = true;
        emit RewardSubmitted(_to, _amount);
    }

    function claim() external {
        address sender = tx.accounts[0].key;
        require(reward[sender].amount > 0, "Reward not existed");
        require(
            reward[sender].lastClaimTime == 0 ||
            block.timestamp >= reward[sender].lastClaimTime + CLAIM_INTERVAL,
            "Claim interval not passed");
        uint256 amountClaim;
        if (reward[sender].lastClaimTime == 0) {
            amountClaim = reward[sender].amountClaimEach;
            uint256 remainder = reward[sender].amount % TOTAL_CLAIM;
            if (remainder != 0) {
                amountClaim += remainder;
            }
        } else if (reward[sender].amount > reward[sender].amountClaimEach) {
            amountClaim = reward[sender].amountClaimEach;
        } else {
            amountClaim = reward[sender].amount;
        }
        (bool success, bytes memory data) = _token.call{accounts: [address(this), sender]}(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success, "Token call failed");
        uint256 balance = abi.decode(data, (uint256));
        require(balance >= amountClaim, "Insufficient amount");
        (success, ) = _token.call{accounts: [address(this), sender]}(
            abi.encodeWithSignature("transfer(address,uint256)", sender, amountClaim)
        );
        require(success, "Token transfer failed");
        reward[sender].amount = reward[sender].amount - amountClaim;
        reward[sender].lastClaimTime = block.timestamp;
        emit AirdropClaimed(sender, amountClaim);
    }
}