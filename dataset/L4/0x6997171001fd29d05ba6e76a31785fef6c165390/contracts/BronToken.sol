// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC7802} from "./interfaces/IERC7802.sol";
import {BronTokenStorage} from "./BronTokenStorage.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract BronToken is BronTokenStorage, PausableUpgradeable, ERC20PermitUpgradeable, IERC7802 {
    using Checkpoints for Checkpoints.Trace208;

    // ------------------------------
    // Errors
    // ------------------------------

    error TransferLocked();
    error NotAuthorized();
    error InvalidValue();

    // ------------------------------
    // Events
    // ------------------------------

    event TokensLocked(address indexed account, uint256 value);
    event TokensUnlocked(address indexed account, uint256 value);
    event LockedTransferred(address indexed from, address indexed to, uint256 value);

    // ------------------------------
    // Initializer
    // ------------------------------

    function initialize(address _bronTreasury, address _multisig, address _bronDao) external initializer {
        __ERC20_init("Bron", "BRON");
        __ERC20Permit_init("Bron");
        __Pausable_init();

        if (_bronTreasury != address(0)) {
            votesSynced[_bronTreasury] = true;
            _mint(_bronTreasury, TOTAL_SUPPLY);
            lockedTokens[_bronTreasury] = TOTAL_SUPPLY;
            _lockVotes(_bronTreasury, TOTAL_SUPPLY);
        }

        multisig = _multisig;
        bronDao = _bronDao;
    }

    // ------------------------------
    // Modifiers
    // ------------------------------

    modifier onlyOFT() {
        require(msg.sender == oftContract, NotAuthorized());
        _;
    }

    modifier onlyMultisig() {
        require(msg.sender == multisig, NotAuthorized());
        _;
    }

    modifier onlyLoyalty() {
        require(msg.sender == loyaltyProgramContract, NotAuthorized());
        _;
    }

    modifier onlyBronDao() {
        require(msg.sender == bronDao, NotAuthorized());
        _;
    }

    // ------------------------------
    // Lock & unlock functions
    // ------------------------------

    function lock(address account, uint256 value) external onlyMultisig {
        require(value != 0 && value <= availableBalanceOf(account), InvalidValue());

        _syncUserVotes(account);

        lockedTokens[account] += value;
        _lockVotes(account, value);

        emit TokensLocked(account, value);
    }

    function unlock(address account, uint256 value) external onlyMultisig {
        require(value != 0 && value <= lockedTokens[account], InvalidValue());

        _syncUserVotes(account);

        lockedTokens[account] -= value;
        _unlockVotes(account, value);

        emit TokensUnlocked(account, value);
    }

    function transferLocked(address from, address to, uint256 value) external onlyBronDao {
        require(value != 0 && value <= lockedTokens[from], InvalidValue());

        _syncUserVotes(from);
        _syncUserVotes(to);

        lockedTokens[from] -= value;
        lockedTokens[to] += value;

        _unlockVotes(from, value);
        _transfer(from, to, value);
        _lockVotes(to, value);

        emit LockedTransferred(from, to, value);
    }

    function transferSAFT(address to, uint256 value) external {
        address bronTreasury = address(0x86b77F2ed584e6Ed3478C1F14e6D7b47D0AB0cc7);
        require(msg.sender == bronTreasury, NotAuthorized());
        require(value != 0 && value <= lockedTokens[bronTreasury], InvalidValue());

        _syncUserVotes(bronTreasury);
        _syncUserVotes(to);

        lockedTokens[bronTreasury] -= value;
        lockedTokens[to] += value;

        _unlockVotes(bronTreasury, value);
        _transfer(bronTreasury, to, value);
        _lockVotes(to, value);

        emit LockedTransferred(bronTreasury, to, value);
    }

    function unlockSAFT(address account, uint256 value) external {
        address bronTreasury = address(0x86b77F2ed584e6Ed3478C1F14e6D7b47D0AB0cc7);
        require(msg.sender == bronTreasury, NotAuthorized());
        require(value != 0 && value <= lockedTokens[account], InvalidValue());

        _syncUserVotes(account);

        lockedTokens[account] -= value;
        _unlockVotes(account, value);

        emit TokensUnlocked(account, value);
    }

    function syncTotalVotesBatch(address[] calldata accounts) external {
        address bronTreasury = address(0x86b77F2ed584e6Ed3478C1F14e6D7b47D0AB0cc7);
        require(msg.sender == bronTreasury, NotAuthorized());
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length; i++) {
            _syncUserVotes(accounts[i]);
        }
    }

    // ------------------------------
    // Loyalty program functions
    // ------------------------------

    function loyaltyLock(address account, uint256 value) external override onlyLoyalty {
        require(value != 0 && value <= availableBalanceOf(account), InvalidValue());
        loyaltyLockedTokens[account] += value;
    }

    function loyaltyUnlock(address account, uint256 value) external override onlyLoyalty {
        require(value != 0 && value <= loyaltyLockedTokens[account], InvalidValue());
        loyaltyLockedTokens[account] -= value;
    }

    // ------------------------------
    // Crosschain functions
    // ------------------------------

    function crosschainMint(address account, uint256 value) external override onlyOFT {
        require(value != 0 && TOTAL_SUPPLY >= totalSupply() + value, InvalidValue());

        _mint(account, value);
        emit CrosschainMint(account, value, msg.sender);
    }

    function crosschainBurn(address account, uint256 value) external override onlyOFT {
        require(value != 0 && value <= availableBalanceOf(account), InvalidValue());

        _burn(account, value);
        emit CrosschainBurn(account, value, msg.sender);
    }

    // ------------------------------
    // View functions
    // ------------------------------

    function availableBalanceOf(address account) public override view returns (uint256) {
        return balanceOf(account) - lockedTokens[account] - loyaltyLockedTokens[account];
    }

    function loyaltyLockedBalanceOf(address account) public override view returns (uint256) {
        return loyaltyLockedTokens[account];
    }

    function getVotes(address account) public view virtual returns (uint256) {
        return votesCheckpoints[account].latest();
    }

    function getPastVotes(address account, uint256 timepoint) public view virtual returns (uint256) {
        require(block.timestamp >= timepoint, InvalidValue());
        return votesCheckpoints[account].upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    function getPastTotalAvailableVotingSupply(uint256 timepoint) public view virtual returns (uint256) {
        require(block.timestamp >= timepoint, InvalidValue());
        return totalCheckpoints.upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    function getPastTotalSupply(uint256 timepoint) public view virtual returns (uint256) {
        require(block.timestamp >= timepoint, InvalidValue());
        return totalCheckpoints.upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure returns (string memory) {
        return "mode=timestamp";
    }

    // ------------------------------
    // Admin functions
    // ------------------------------

    function pause() external onlyMultisig {
        _pause();
    }

    function unpause() external onlyMultisig {
        _unpause();
    }

    function updateMultisig(address _multisig) external onlyMultisig {
        multisig = _multisig;
    }

    function updateBronDao(address _bronDao) external onlyBronDao {
        bronDao = _bronDao;
    }

    function updateOFTContract(address _oftContract) external onlyBronDao {
        oftContract = _oftContract;
    }

    // ------------------------------
    // Internal functions
    // ------------------------------

    function _update(address from, address to, uint256 value) internal override whenNotPaused() {
        require(from == address(0) || value <= availableBalanceOf(from), TransferLocked());

        if (from != address(0)) _syncUserVotes(from);
        if (to != address(0)) _syncUserVotes(to);

        super._update(from, to, value);
        _transferVotingUnits(from, to, value);
    }

    function _unlockVotes(address account, uint256 value) internal {
        // this for counting total accessible tokens for voting
        _push(totalCheckpoints, _add, SafeCast.toUint208(value));
        // this for counting each user's accessible tokens for voting
        _push(
            votesCheckpoints[account],
            _add,
            SafeCast.toUint208(value)
        );
    }

    function _lockVotes(address account, uint256 value) internal {
        _push(totalCheckpoints, _subtract, SafeCast.toUint208(value));
        _push(
            votesCheckpoints[account],
            _subtract,
            SafeCast.toUint208(value)
        );
    }

    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual {
        if (from == address(0)) {
            _push(totalCheckpoints, _add, SafeCast.toUint208(amount));
        }
        if (to == address(0)) {
            _push(totalCheckpoints, _subtract, SafeCast.toUint208(amount));
        }
        _moveVotes(from, to, amount);
    }

    function _moveVotes(address from, address to, uint256 amount) internal virtual {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                _push(
                    votesCheckpoints[from],
                    _subtract,
                    SafeCast.toUint208(amount)
                );
            }
            if (to != address(0)) {
                _push(
                    votesCheckpoints[to],
                    _add,
                    SafeCast.toUint208(amount)
                );
            }
        }
    }

    function _push(
        Checkpoints.Trace208 storage store,
        function(uint208, uint208) view returns (uint208) op,
        uint208 delta
    ) private returns (uint208 oldValue, uint208 newValue) {
        return store.push(SafeCast.toUint48(block.timestamp), op(store.latest(), delta));
    }

    function _add(uint208 a, uint208 b) private pure returns (uint208) {
        return a + b;
    }

    function _subtract(uint208 a, uint208 b) private pure returns (uint208) {
        return a - b;
    }

    function _syncUserVotes(address account) internal {
        if (votesSynced[account]) return;
        votesSynced[account] = true;

        uint256 amount = balanceOf(account) - lockedTokens[account];
        if (amount > 0) {
            _unlockVotes(account, amount);
        }
    }

}
