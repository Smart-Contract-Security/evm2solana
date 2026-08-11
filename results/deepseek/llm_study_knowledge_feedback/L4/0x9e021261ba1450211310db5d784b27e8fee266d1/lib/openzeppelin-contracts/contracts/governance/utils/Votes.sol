// SPDX-License-Identifier: MIT

import {AccountInfo} from "solana";

abstract contract Votes {
    using Checkpoints for Checkpoints.Trace208;

    bytes32 private constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address account => address) private _delegatee;

    mapping(address delegatee => Checkpoints.Trace208) private _delegateCheckpoints;

    Checkpoints.Trace208 private _totalCheckpoints;

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint64 previousVotes, uint64 newVotes);

    function clock() public view returns (uint48) {
        return Time.blockNumber();
    }

    function CLOCK_MODE() public view returns (string memory) {
        if (clock() != Time.blockNumber()) {
            revert("ERC6372InconsistentClock");
        }
        return "mode=blocknumber&from=default";
    }

    function _validateTimepoint(uint64 timepoint) internal view returns (uint48) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) revert("ERC5805FutureLookup");
        return uint48(timepoint);
    }

    function getVotes(address account) public view virtual returns (uint64) {
        return uint64(_delegateCheckpoints[account].latest());
    }

    function getPastVotes(address account, uint64 timepoint) public view virtual returns (uint64) {
        return uint64(_delegateCheckpoints[account].upperLookupRecent(_validateTimepoint(timepoint)));
    }

    function getPastTotalSupply(uint64 timepoint) public view virtual returns (uint64) {
        return uint64(_totalCheckpoints.upperLookupRecent(_validateTimepoint(timepoint)));
    }

    function _getTotalSupply() internal view virtual returns (uint64) {
        return uint64(_totalCheckpoints.latest());
    }

    function delegates(address account) public view virtual returns (address) {
        return _delegatee[account];
    }

    function delegate(address delegatee) public virtual {
        address account = tx.accounts.dataAccount.key;
        _delegate(account, delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint64 nonce,
        uint64 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > expiry) {
            revert("VotesExpiredSignature");
        }
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = _ecrecover(hash, v, r, s);
        require(signer != address(0), "Votes: invalid signature");
        _useCheckedNonce(signer, nonce);
        _delegate(signer, delegatee);
    }

    function _ecrecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        bytes32 ethHash = keccak256(abi.encodePacked(message));
        return address(uint160(uint256(keccak256(abi.encodePacked(ethHash, signature)))));
    }

    function _delegate(address account, address delegatee) internal virtual {
        address oldDelegate = delegates(account);
        _delegatee[account] = delegatee;

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    }

    function _transferVotingUnits(address from, address to, uint64 amount) internal virtual {
        if (from == address(0)) {
            _push(_totalCheckpoints, _add, uint208(amount));
        }
        if (to == address(0)) {
            _push(_totalCheckpoints, _subtract, uint208(amount));
        }
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    function _moveDelegateVotes(address from, address to, uint64 amount) internal virtual {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                (uint64 oldValue, uint64 newValue) = _push(
                    _delegateCheckpoints[from],
                    _subtract,
                    uint208(amount)
                );
                emit DelegateVotesChanged(from, oldValue, newValue);
            }
            if (to != address(0)) {
                (uint64 oldValue, uint64 newValue) = _push(
                    _delegateCheckpoints[to],
                    _add,
                    uint208(amount)
                );
                emit DelegateVotesChanged(to, oldValue, newValue);
            }
        }
    }

    function _numCheckpoints(address account) internal view virtual returns (uint32) {
        return uint32(_delegateCheckpoints[account].length());
    }

    function _checkpoints(
        address account,
        uint32 pos
    ) internal view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _delegateCheckpoints[account].at(pos);
    }

    function _push(
        Checkpoints.Trace208 storage store,
        function(uint208, uint208) view returns (uint208) op,
        uint208 delta
    ) private returns (uint64 oldValue, uint64 newValue) {
        return store.push(clock(), op(store.latest(), delta));
    }

    function _add(uint208 a, uint208 b) private pure returns (uint208) {
        return a + b;
    }

    function _subtract(uint208 a, uint208 b) private pure returns (uint208) {
        return a - b;
    }

    function _getVotingUnits(address) internal view virtual returns (uint64);

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32);

    function _useCheckedNonce(address signer, uint64 nonce) internal virtual;
}

library Checkpoints {
    struct Trace208 {
        mapping(uint48 => uint208) _checkpoints;
        uint48[] _keys;
    }

    struct Checkpoint208 {
        uint48 key;
        uint208 value;
    }

    function latest(Trace208 storage self) internal view returns (uint208) {
        uint256 len = self._keys.length;
        if (len == 0) return 0;
        return self._checkpoints[self._keys[len - 1]];
    }

    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._keys.length;
        if (len == 0) return 0;
        for (uint256 i = len; i > 0; i--) {
            if (self._keys[i - 1] <= key) {
                return self._checkpoints[self._keys[i - 1]];
            }
        }
        return 0;
    }

    function push(
        Trace208 storage self,
        uint48 key,
        uint208 value
    ) internal returns (uint64 oldValue, uint64 newValue) {
        oldValue = uint64(latest(self));
        newValue = uint64(value);
        uint256 len = self._keys.length;
        if (len > 0 && self._keys[len - 1] == key) {
            self._checkpoints[key] = value;
        } else {
            self._keys.push(key);
            self._checkpoints[key] = value;
        }
    }

    function length(Trace208 storage self) internal view returns (uint256) {
        return self._keys.length;
    }

    function at(Trace208 storage self, uint32 pos) internal view returns (Checkpoint208 memory) {
        require(pos < self._keys.length, "Checkpoints: index out of bounds");
        uint48 key = self._keys[pos];
        uint208 value = self._checkpoints[key];
        return Checkpoint208(key, value);
    }
}

library Time {
    function blockNumber() internal view returns (uint48) {
        return uint48(block.number);
    }
}