import {Math} from "../../../utils/math/Math.sol";

abstract contract ERC20Votes {
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    bytes32 private constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address => address) private _delegates;
    mapping(address => Checkpoint[]) private _checkpoints;
    Checkpoint[] private _totalSupplyCheckpoints;

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    function clock() public view virtual returns (uint64) {
        return uint64(block.number);
    }

    function CLOCK_MODE() public view virtual returns (string memory) {
        require(clock() == block.number, "ERC20Votes: broken clock mode");
        return "mode=blocknumber&from=default";
    }

    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoint memory) {
        return _checkpoints[account][pos];
    }

    function numCheckpoints(address account) public view virtual returns (uint32) {
        return uint32(_checkpoints[account].length);
    }

    function delegates(address account) public view virtual returns (address) {
        return _delegates[account];
    }

    function getVotes(address account) public view virtual returns (uint256) {
        uint256 pos = _checkpoints[account].length;
        unchecked {
            return pos == 0 ? 0 : _checkpoints[account][pos - 1].votes;
        }
    }

    function getPastVotes(address account, uint256 timepoint) public view virtual returns (uint256) {
        require(timepoint < clock(), "ERC20Votes: future lookup");
        return _checkpointsLookup(_checkpoints[account], timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) public view virtual returns (uint256) {
        require(timepoint < clock(), "ERC20Votes: future lookup");
        return _checkpointsLookup(_totalSupplyCheckpoints, timepoint);
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 timepoint) private view returns (uint256) {
        uint256 length = ckpts.length;

        uint256 low = 0;
        uint256 high = length;

        if (length > 5) {
            uint256 mid = length - Math.sqrt(length);
            if (_unsafeAccess(ckpts, mid).fromBlock > timepoint) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(ckpts, mid).fromBlock > timepoint) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        unchecked {
            return high == 0 ? 0 : _unsafeAccess(ckpts, high - 1).votes;
        }
    }

    function delegate(address delegatee) public virtual {
        _delegate(tx.accounts.dataAccount.key, delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(block.timestamp <= expiry, "ERC20Votes: signature expired");
        bytes32 structHash = keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
        address signer = _ecrecover(hash, v, r, s);
        require(nonce == _useNonce(signer), "ERC20Votes: invalid nonce");
        _delegate(signer, delegatee);
    }

    function _ecrecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        bytes memory signature = new bytes(65);
        signature[0] = bytes1(r);
        signature[1] = bytes1(r >> 8);
        signature[2] = bytes1(r >> 16);
        signature[3] = bytes1(r >> 24);
        signature[4] = bytes1(r >> 32);
        signature[5] = bytes1(r >> 40);
        signature[6] = bytes1(r >> 48);
        signature[7] = bytes1(r >> 56);
        signature[8] = bytes1(r >> 64);
        signature[9] = bytes1(r >> 72);
        signature[10] = bytes1(r >> 80);
        signature[11] = bytes1(r >> 88);
        signature[12] = bytes1(r >> 96);
        signature[13] = bytes1(r >> 104);
        signature[14] = bytes1(r >> 112);
        signature[15] = bytes1(r >> 120);
        signature[16] = bytes1(r >> 128);
        signature[17] = bytes1(r >> 136);
        signature[18] = bytes1(r >> 144);
        signature[19] = bytes1(r >> 152);
        signature[20] = bytes1(r >> 160);
        signature[21] = bytes1(r >> 168);
        signature[22] = bytes1(r >> 176);
        signature[23] = bytes1(r >> 184);
        signature[24] = bytes1(r >> 192);
        signature[25] = bytes1(r >> 200);
        signature[26] = bytes1(r >> 208);
        signature[27] = bytes1(r >> 216);
        signature[28] = bytes1(r >> 224);
        signature[29] = bytes1(r >> 232);
        signature[30] = bytes1(r >> 240);
        signature[31] = bytes1(r >> 248);

        signature[32] = bytes1(s);
        signature[33] = bytes1(s >> 8);
        signature[34] = bytes1(s >> 16);
        signature[35] = bytes1(s >> 24);
        signature[36] = bytes1(s >> 32);
        signature[37] = bytes1(s >> 40);
        signature[38] = bytes1(s >> 48);
        signature[39] = bytes1(s >> 56);
        signature[40] = bytes1(s >> 64);
        signature[41] = bytes1(s >> 72);
        signature[42] = bytes1(s >> 80);
        signature[43] = bytes1(s >> 88);
        signature[44] = bytes1(s >> 96);
        signature[45] = bytes1(s >> 104);
        signature[46] = bytes1(s >> 112);
        signature[47] = bytes1(s >> 120);
        signature[48] = bytes1(s >> 128);
        signature[49] = bytes1(s >> 136);
        signature[50] = bytes1(s >> 144);
        signature[51] = bytes1(s >> 152);
        signature[52] = bytes1(s >> 160);
        signature[53] = bytes1(s >> 168);
        signature[54] = bytes1(s >> 176);
        signature[55] = bytes1(s >> 184);
        signature[56] = bytes1(s >> 192);
        signature[57] = bytes1(s >> 200);
        signature[58] = bytes1(s >> 208);
        signature[59] = bytes1(s >> 216);
        signature[60] = bytes1(s >> 224);
        signature[61] = bytes1(s >> 232);
        signature[62] = bytes1(s >> 240);
        signature[63] = bytes1(s >> 248);

        signature[64] = bytes1(v);

        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        bytes32 ethHash = keccak256(abi.encodePacked(messageHash));

        address recovered;
        bytes memory input = abi.encodePacked(ethHash, signature);
        assembly {
            recovered := create(0, add(input, 0x20), mload(input))
        }
        return recovered;
    }

    function _domainSeparatorV4() internal view virtual returns (bytes32) {}

    function _useNonce(address owner) internal virtual returns (uint256) {}

    function _maxSupply() internal view virtual returns (uint224) {
        return type(uint224).max;
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(totalSupply() <= _maxSupply(), "ERC20Votes: total supply risks overflowing votes");
        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {
        _moveVotingPower(delegates(from), delegates(to), amount);
    }

    function totalSupply() internal view virtual returns (uint256) {}

    function balanceOf(address account) internal view virtual returns (uint256) {}

    function _delegate(address delegator, address delegatee) internal virtual {
        address currentDelegate = delegates(delegator);
        uint256 delegatorBalance = balanceOf(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveVotingPower(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveVotingPower(address src, address dst, uint256 amount) private {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[src], _subtract, amount);
                emit DelegateVotesChanged(src, oldWeight, newWeight);
            }

            if (dst != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[dst], _add, amount);
                emit DelegateVotesChanged(dst, oldWeight, newWeight);
            }
        }
    }

    function _writeCheckpoint(
        Checkpoint[] storage ckpts,
        function(uint256, uint256) internal pure returns (uint256) op,
        uint256 delta
    ) private returns (uint256 oldWeight, uint256 newWeight) {
        uint256 pos = ckpts.length;

        unchecked {
            Checkpoint memory oldCkpt = pos == 0 ? Checkpoint(0, 0) : _unsafeAccess(ckpts, pos - 1);

            oldWeight = oldCkpt.votes;
            newWeight = op(oldWeight, delta);

            if (pos > 0 && oldCkpt.fromBlock == clock()) {
                _unsafeAccess(ckpts, pos - 1).votes = uint224(newWeight);
            } else {
                ckpts.push(Checkpoint({fromBlock: uint32(clock()), votes: uint224(newWeight)}));
            }
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }

    function _unsafeAccess(Checkpoint[] storage ckpts, uint256 pos) private pure returns (Checkpoint storage result) {
        uint256 slot;
        assembly {
            slot := ckpts.slot
        }
        uint256 base = uint256(keccak256(abi.encode(slot)));
        assembly {
            result.slot := add(base, pos)
        }
    }
}