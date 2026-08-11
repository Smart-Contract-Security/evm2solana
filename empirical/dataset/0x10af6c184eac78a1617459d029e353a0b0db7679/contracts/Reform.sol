// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Reform
 * @notice $REFORM — 100M supply ERC-20 with built-in pull-based reward accumulator.
 *         Hook is the sole minter (set once). On each BUY, hook calls depositReward(amount)
 *         which mints `amount` to this contract and bumps accTokensPerShare.
 *         Holders claim() their pro-rata share at any time.
 *
 *         Auto-settles rewards on every transfer (so debt math stays correct).
 *         Excluded addresses (LP/hook/dead/pool manager/position manager) don't earn.
 */
contract Reform is ERC20, Ownable {
    uint256 public accTokensPerShare;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public totalClaimed;

    mapping(address => bool) public isExcludedFromRewards;
    uint256 public excludedSupply;

    address public minter;

    event RewardDeposited(uint256 amount, uint256 newAccPerShare);
    event RewardClaimed(address indexed user, uint256 amount);
    event MinterSet(address indexed minter);
    event ExclusionSet(address indexed account, bool excluded);

    error NotMinter();
    error NothingToClaim();
    error MinterAlreadySet();

    constructor(address initialHolder_) ERC20("Reform", "REFORM") Ownable(msg.sender) {
        _mint(initialHolder_, 100_000_000 ether);
    }

    function setMinter(address minter_) external onlyOwner {
        if (minter != address(0)) revert MinterAlreadySet();
        minter = minter_;
        _setExcluded(minter_, true);
        _setExcluded(address(this), true);
        emit MinterSet(minter_);
    }

    function setExcludedFromRewards(address account, bool excluded) external onlyOwner {
        _setExcluded(account, excluded);
    }

    function _setExcluded(address account, bool excluded) internal {
        if (isExcludedFromRewards[account] == excluded) return;
        _settle(account);
        isExcludedFromRewards[account] = excluded;
        uint256 bal = balanceOf(account);
        if (excluded) {
            excludedSupply += bal;
        } else {
            excludedSupply -= bal;
            rewardDebt[account] = (bal * accTokensPerShare) / 1e18;
        }
        emit ExclusionSet(account, excluded);
    }

    /// @notice Hook mints reward tokens into this contract and bumps the accumulator.
    function depositReward(uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        if (amount == 0) return;

        uint256 eligibleSupply = totalSupply() - excludedSupply;
        if (eligibleSupply == 0) {
            _mint(address(0xdead), amount);
            return;
        }

        _mint(address(this), amount);
        accTokensPerShare += (amount * 1e18) / eligibleSupply;
        emit RewardDeposited(amount, accTokensPerShare);
    }

    /// @notice Surprise mint — uncapped, hook-only. Goes straight to recipient (no accumulator).
    function surpriseMint(address recipient, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        if (amount == 0) return;
        _mint(recipient, amount);
    }

    function claim() external returns (uint256 claimed) {
        claimed = pendingRewards(msg.sender);
        if (claimed == 0) revert NothingToClaim();
        rewardDebt[msg.sender] = (balanceOf(msg.sender) * accTokensPerShare) / 1e18;
        totalClaimed[msg.sender] += claimed;
        _transfer(address(this), msg.sender, claimed);
        emit RewardClaimed(msg.sender, claimed);
    }

    function pendingRewards(address user) public view returns (uint256) {
        if (isExcludedFromRewards[user]) return 0;
        uint256 bal = balanceOf(user);
        uint256 accrued = (bal * accTokensPerShare) / 1e18;
        if (accrued <= rewardDebt[user]) return 0;
        return accrued - rewardDebt[user];
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) _settle(from);
        if (to != address(0)) _settle(to);

        super._update(from, to, value);

        if (from != address(0) && isExcludedFromRewards[from]) excludedSupply -= value;
        if (to != address(0) && isExcludedFromRewards[to]) excludedSupply += value;

        if (from != address(0) && !isExcludedFromRewards[from]) {
            rewardDebt[from] = (balanceOf(from) * accTokensPerShare) / 1e18;
        }
        if (to != address(0) && !isExcludedFromRewards[to]) {
            rewardDebt[to] = (balanceOf(to) * accTokensPerShare) / 1e18;
        }
    }

    function _settle(address account) internal {
        if (isExcludedFromRewards[account]) return;
        uint256 bal = balanceOf(account);
        if (bal == 0) return;
        uint256 accrued = (bal * accTokensPerShare) / 1e18;
        uint256 debt = rewardDebt[account];
        if (accrued <= debt) return;
        uint256 owed = accrued - debt;
        rewardDebt[account] = accrued;
        totalClaimed[account] += owed;
        _transfer(address(this), account, owed);
        emit RewardClaimed(account, owed);
    }
}
