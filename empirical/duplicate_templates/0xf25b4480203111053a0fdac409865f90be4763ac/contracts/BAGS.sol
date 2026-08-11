// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BAGS
 * @notice Beta Alpha Gamma Sigma ($BAGS) — 1,000,000,000 (1B) fixed-supply ERC-20 with a
 *         built-in, pull-based reward accumulator (MasterChef-style "accTokensPerShare").
 *
 * ─────────────────────────────────────────────────────────────────────────────────────────
 *  REWARD MECHANISM (how holders earn $BAGS just by holding)
 * ─────────────────────────────────────────────────────────────────────────────────────────
 *
 *  The BAGSHook is the only "bagger" (set once via setBagger). On every BUY of $BAGS, the
 *  hook mints a reward — 3% of the tokens the buyer received — and calls fillBag(amount).
 *  Those freshly minted tokens are distributed pro-rata to every *eligible* holder. Holding
 *  $BAGS therefore earns you a share of all subsequent buy pressure. Sells are not rewarded.
 *
 *  The accumulator (no loops, O(1) per holder):
 *
 *   • accTokensPerShare — a running total of "reward tokens earned per 1 token held", scaled
 *     by 1e18. fillBag(amount) mints `amount` into THIS contract (a holding vault) and bumps:
 *         accTokensPerShare += amount * 1e18 / eligibleSupply
 *     where eligibleSupply = totalSupply - excludedSupply (the bagless balances).
 *
 *   • rewardDebt[user] — the portion of accTokensPerShare a user has *already* accounted for.
 *     Set to (balance * accTokensPerShare / 1e18) whenever their balance changes. It is the
 *     "high-water mark" so a holder only earns on accumulator growth that happened while they
 *     held their tokens — not retroactively.
 *
 *   • pendingBag(user) = balance * accTokensPerShare / 1e18 - rewardDebt[user]
 *     i.e. everything accrued since their debt was last set. secureBag() pays it out from the
 *     vault and resets the debt to zero-out pending.
 *
 *  Auto-settle: _update() (every mint/burn/transfer) calls _settle() on both parties BEFORE
 *  moving tokens, paying out any pending reward and then resetting rewardDebt to the new
 *  balance. This keeps the debt math exact across transfers — you never need to secureBag()
 *  "before" moving tokens; receiving or sending $BAGS settles you automatically. (Consequence:
 *  a buyer's own reward is auto-settled when they receive their swap output, so standing
 *  pendingBag only accrues to holders who are passive during a *later* buy.)
 *
 *  Bagless addresses (the hook, this contract, 0xdead, PoolManager, PositionManager, LP) are
 *  excluded from rewards: they don't earn and their balances are removed from eligibleSupply
 *  via excludedSupply, so rewards aren't wasted on the pool/system. If eligibleSupply is ever
 *  zero at the moment of a buy (e.g. 100% of supply still in the LP, no holders yet), that
 *  buy's reward is minted to 0xdead instead of being distributed.
 * ─────────────────────────────────────────────────────────────────────────────────────────
 */
contract BAGS is ERC20, Ownable {
    uint256 public accTokensPerShare;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public totalClaimed;

    mapping(address => bool) public isBagless;
    uint256 public excludedSupply;

    address public bagger;

    event BagFilled(uint256 amount, uint256 newAccPerShare);
    event BagSecured(address indexed user, uint256 amount);
    event BaggerSet(address indexed bagger);
    event BaglessSet(address indexed account, bool bagless);

    error NotBagger();
    error NothingToSecure();
    error BaggerAlreadySet();

    constructor(address initialHolder_) ERC20("Beta Alpha Gamma Sigma", "BAGS") Ownable(msg.sender) {
        _mint(initialHolder_, 1_000_000_000 ether);
    }

    function setBagger(address bagger_) external onlyOwner {
        if (bagger != address(0)) revert BaggerAlreadySet();
        bagger = bagger_;
        _setBagless(bagger_, true);
        _setBagless(address(this), true);
        emit BaggerSet(bagger_);
    }

    function setBagless(address account, bool bagless) external onlyOwner {
        _setBagless(account, bagless);
    }

    function _setBagless(address account, bool bagless) internal {
        if (isBagless[account] == bagless) return;
        _settle(account);
        isBagless[account] = bagless;
        uint256 bal = balanceOf(account);
        if (bagless) {
            excludedSupply += bal;
        } else {
            excludedSupply -= bal;
            rewardDebt[account] = (bal * accTokensPerShare) / 1e18;
        }
        emit BaglessSet(account, bagless);
    }

    /// @notice Bagger mints reward tokens into this contract and bumps the accumulator.
    function fillBag(uint256 amount) external {
        if (msg.sender != bagger) revert NotBagger();
        if (amount == 0) return;

        uint256 eligibleSupply = totalSupply() - excludedSupply;
        if (eligibleSupply == 0) {
            _mint(address(0xdead), amount);
            return;
        }

        _mint(address(this), amount);
        accTokensPerShare += (amount * 1e18) / eligibleSupply;
        emit BagFilled(amount, accTokensPerShare);
    }

    /// @notice Drop a bag — uncapped, bagger-only. Goes straight to recipient (no accumulator).
    function dropBag(address recipient, uint256 amount) external {
        if (msg.sender != bagger) revert NotBagger();
        if (amount == 0) return;
        _mint(recipient, amount);
    }

    function secureBag() external returns (uint256 secured) {
        secured = pendingBag(msg.sender);
        if (secured == 0) revert NothingToSecure();
        rewardDebt[msg.sender] = (balanceOf(msg.sender) * accTokensPerShare) / 1e18;
        totalClaimed[msg.sender] += secured;
        _transfer(address(this), msg.sender, secured);
        emit BagSecured(msg.sender, secured);
    }

    function pendingBag(address user) public view returns (uint256) {
        if (isBagless[user]) return 0;
        uint256 bal = balanceOf(user);
        uint256 accrued = (bal * accTokensPerShare) / 1e18;
        if (accrued <= rewardDebt[user]) return 0;
        return accrued - rewardDebt[user];
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) _settle(from);
        if (to != address(0)) _settle(to);

        super._update(from, to, value);

        if (from != address(0) && isBagless[from]) excludedSupply -= value;
        if (to != address(0) && isBagless[to]) excludedSupply += value;

        if (from != address(0) && !isBagless[from]) {
            rewardDebt[from] = (balanceOf(from) * accTokensPerShare) / 1e18;
        }
        if (to != address(0) && !isBagless[to]) {
            rewardDebt[to] = (balanceOf(to) * accTokensPerShare) / 1e18;
        }
    }

    function _settle(address account) internal {
        if (isBagless[account]) return;
        uint256 bal = balanceOf(account);
        if (bal == 0) return;
        uint256 accrued = (bal * accTokensPerShare) / 1e18;
        uint256 debt = rewardDebt[account];
        if (accrued <= debt) return;
        uint256 owed = accrued - debt;
        rewardDebt[account] = accrued;
        totalClaimed[account] += owed;
        _transfer(address(this), account, owed);
        emit BagSecured(account, owed);
    }
}
