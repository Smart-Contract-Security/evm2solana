// SPDX-License-Identifier: MIT
import "solana";

contract DreamverseAirdrop {
    bytes32 public constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    string private constant MESSAGE = "Dreamverse_Airdrop";
    uint64 public TOTAL_CLAIM = 12;
    uint64 public constant CLAIM_INTERVAL = 30 days;

    address private _admin;
    address private _execute;
    address private _token;

    mapping(uint64 => bool) private submitted;
    mapping(address => AirdropInfo) public reward;

    struct AirdropInfo {
        uint64 lastClaimTime;
        uint64 amount;
        uint64 amountClaimEach;
    }

    event AirdropClaimed(address _user, uint64 _amount);
    event RewardSubmitted(address _user, uint64 _amount);

    constructor(address _executeAddr, address _tokenAddr) {
        _admin = tx.accounts.dataAccount.key;
        _execute = _executeAddr;
        _token = _tokenAddr;
    }

    function hasRole(bytes32 role, address account) private view returns (bool) {
        if (role == EXECUTE_ROLE) {
            return account == _execute;
        }
        if (role == keccak256("DEFAULT_ADMIN_ROLE")) {
            return account == _admin;
        }
        return false;
    }

    function verify(
        uint64 _id,
        address _to,
        uint64 _amount,
        string memory _message,
        bytes memory signature
    ) private pure returns (address) {
        bytes memory encoded = abi.encodePacked(_id, _to, _amount, _message);
        bytes32 messageHash = keccak256(encoded);
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory combined = new bytes(prefix.length + 32);
        for (uint i = 0; i < prefix.length; i++) {
            combined[i] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            combined[prefix.length + i] = messageHash[i];
        }
        bytes32 ethSignedMessageHash = keccak256(combined);
        return recoverSigner(ethSignedMessageHash, signature);
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) private pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");
        r = bytes32(uint256(uint8(sig[0])) << 248 |
                   uint256(uint8(sig[1])) << 240 |
                   uint256(uint8(sig[2])) << 232 |
                   uint256(uint8(sig[3])) << 224 |
                   uint256(uint8(sig[4])) << 216 |
                   uint256(uint8(sig[5])) << 208 |
                   uint256(uint8(sig[6])) << 200 |
                   uint256(uint8(sig[7])) << 192 |
                   uint256(uint8(sig[8])) << 184 |
                   uint256(uint8(sig[9])) << 176 |
                   uint256(uint8(sig[10])) << 168 |
                   uint256(uint8(sig[11])) << 160 |
                   uint256(uint8(sig[12])) << 152 |
                   uint256(uint8(sig[13])) << 144 |
                   uint256(uint8(sig[14])) << 136 |
                   uint256(uint8(sig[15])) << 128 |
                   uint256(uint8(sig[16])) << 120 |
                   uint256(uint8(sig[17])) << 112 |
                   uint256(uint8(sig[18])) << 104 |
                   uint256(uint8(sig[19])) << 96 |
                   uint256(uint8(sig[20])) << 88 |
                   uint256(uint8(sig[21])) << 80 |
                   uint256(uint8(sig[22])) << 72 |
                   uint256(uint8(sig[23])) << 64 |
                   uint256(uint8(sig[24])) << 56 |
                   uint256(uint8(sig[25])) << 48 |
                   uint256(uint8(sig[26])) << 40 |
                   uint256(uint8(sig[27])) << 32 |
                   uint256(uint8(sig[28])) << 24 |
                   uint256(uint8(sig[29])) << 16 |
                   uint256(uint8(sig[30])) << 8 |
                   uint256(uint8(sig[31])));
        s = bytes32(uint256(uint8(sig[32])) << 248 |
                   uint256(uint8(sig[33])) << 240 |
                   uint256(uint8(sig[34])) << 232 |
                   uint256(uint8(sig[35])) << 224 |
                   uint256(uint8(sig[36])) << 216 |
                   uint256(uint8(sig[37])) << 208 |
                   uint256(uint8(sig[38])) << 200 |
                   uint256(uint8(sig[39])) << 192 |
                   uint256(uint8(sig[40])) << 184 |
                   uint256(uint8(sig[41])) << 176 |
                   uint256(uint8(sig[42])) << 168 |
                   uint256(uint8(sig[43])) << 160 |
                   uint256(uint8(sig[44])) << 152 |
                   uint256(uint8(sig[45])) << 144 |
                   uint256(uint8(sig[46])) << 136 |
                   uint256(uint8(sig[47])) << 128 |
                   uint256(uint8(sig[48])) << 120 |
                   uint256(uint8(sig[49])) << 112 |
                   uint256(uint8(sig[50])) << 104 |
                   uint256(uint8(sig[51])) << 96 |
                   uint256(uint8(sig[52])) << 88 |
                   uint256(uint8(sig[53])) << 80 |
                   uint256(uint8(sig[54])) << 72 |
                   uint256(uint8(sig[55])) << 64 |
                   uint256(uint8(sig[56])) << 56 |
                   uint256(uint8(sig[57])) << 48 |
                   uint256(uint8(sig[58])) << 40 |
                   uint256(uint8(sig[59])) << 32 |
                   uint256(uint8(sig[60])) << 24 |
                   uint256(uint8(sig[61])) << 16 |
                   uint256(uint8(sig[62])) << 8 |
                   uint256(uint8(sig[63])));
        v = uint8(sig[64]);
        if (v < 27) {
            v += 27;
        }
        require(v == 27 || v == 28, "invalid signature v value");
    }

    function ecrecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hash, v, r, s)))));
    }

    function submitReward(
        uint64 _id,
        address _to,
        uint64 _amount,
        bytes calldata signature
    ) external {
        require(hasRole(EXECUTE_ROLE, verify(_id, _to, _amount, MESSAGE, signature)), "Signer does not have EXECUTE_ROLE");
        require(!submitted[_id], "Request already submitted");
        require(reward[_to].amountClaimEach == 0, "User already register airdrop");
        require(tx.accounts.dataAccount.key == _to, "Sender must be equal to recipient");

        AirdropInfo memory airdrop;
        airdrop.amount = _amount;
        airdrop.amountClaimEach = _amount / TOTAL_CLAIM;
        reward[_to] = airdrop;
        submitted[_id] = true;
        emit RewardSubmitted(_to, _amount);
    }

    function claim() external {
        address sender = tx.accounts.dataAccount.key;
        require(reward[sender].amount > 0, "Reward not existed");
        require(
            reward[sender].lastClaimTime == 0 ||
            block.timestamp >= reward[sender].lastClaimTime + CLAIM_INTERVAL,
            "Claim interval not passed");

        uint64 amountClaim;
        if (reward[sender].lastClaimTime == 0) {
            amountClaim = reward[sender].amountClaimEach;
            uint64 remainder = reward[sender].amount % TOTAL_CLAIM;
            if (remainder != 0) {
                amountClaim += remainder;
            }
        } else if (reward[sender].amount > reward[sender].amountClaimEach) {
            amountClaim = reward[sender].amountClaimEach;
        } else {
            amountClaim = reward[sender].amount;
        }

        require(amountClaim > 0, "Nothing to claim");
        
        reward[sender].amount = reward[sender].amount - amountClaim;
        reward[sender].lastClaimTime = uint64(block.timestamp);
        emit AirdropClaimed(sender, amountClaim);
    }

    function getTokenBalance() external view returns (uint64) {
        return 0;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }

    function getExecute() external view returns (address) {
        return _execute;
    }

    function getToken() external view returns (address) {
        return _token;
    }
}