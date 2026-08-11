// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CIRC
 * @notice Recirculate ($CIRC) — 1,000,000,000 (1B) fixed-supply ERC-20 with a built-in,
 *         pull-based reward accumulator (MasterChef-style "accTokensPerShare").
 *
 * ─────────────────────────────────────────────────────────────────────────────────────────
 *  REWARD MECHANISM (how holders earn $CIRC just by holding — value "recirculates" to them)
 * ─────────────────────────────────────────────────────────────────────────────────────────
 *
 *  The CIRCHook is the only "circulator" (set once via setCirculator). On every BUY of $CIRC,
 *  the hook mints a reward — 6% of the tokens the buyer received — and calls injectFlow(amount).
 *  Those freshly minted tokens are distributed pro-rata to every holder still *in circulation*
 *  (i.e. not stagnant). Holding $CIRC therefore recirculates a share of all buy pressure back
 *  to you. Sells are not rewarded.
 *
 *  The accumulator (no loops, O(1) per holder):
 *
 *   • accTokensPerShare — a running total of "reward tokens earned per 1 token held", scaled
 *     by 1e18. injectFlow(amount) mints `amount` into THIS contract (a holding vault) and bumps:
 *         accTokensPerShare += amount * 1e18 / eligibleSupply
 *     where eligibleSupply = totalSupply - excludedSupply (the stagnant balances).
 *
 *   • rewardDebt[user] — the portion of accTokensPerShare a user has *already* accounted for.
 *     Set to (balance * accTokensPerShare / 1e18) whenever their balance changes. It is the
 *     "high-water mark" so a holder only earns on accumulator growth that happened while they
 *     held their tokens — not retroactively.
 *
 *   • pendingFlow(user) = balance * accTokensPerShare / 1e18 - rewardDebt[user]
 *     i.e. everything accrued since their debt was last set. recirculate() pays it out from the
 *     vault and resets the debt to zero-out pending.
 *
 *  Auto-settle: _update() (every mint/burn/transfer) calls _settle() on both parties BEFORE
 *  moving tokens, paying out any pending reward and then resetting rewardDebt to the new
 *  balance. This keeps the debt math exact across transfers — you never need to recirculate()
 *  "before" moving tokens; receiving or sending $CIRC settles you automatically. (Consequence:
 *  a buyer's own reward is auto-settled when they receive their swap output, so standing
 *  pendingFlow only accrues to holders who are passive during a *later* buy.)
 *
 *  Stagnant addresses (the hook, this contract, 0xdead, PoolManager, PositionManager, LP) are
 *  excluded from rewards: they don't earn and their balances are removed from eligibleSupply
 *  via excludedSupply, so rewards aren't wasted on the pool/system. If eligibleSupply is ever
 *  zero at the moment of a buy (e.g. 100% of supply still in the LP, no holders yet), that
 *  buy's reward is minted to 0xdead instead of being distributed.
 * ─────────────────────────────────────────────────────────────────────────────────────────
 */
contract CIRC is ERC20, Ownable {
    uint256 public accTokensPerShare;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public totalClaimed;

    mapping(address => bool) public isStagnant;
    uint256 public excludedSupply;

    address public circulator;

    event FlowInjected(uint256 amount, uint256 newAccPerShare);
    event Recirculated(address indexed user, uint256 amount);
    event CirculatorSet(address indexed circulator);
    event StagnantSet(address indexed account, bool stagnant);

    error NotCirculator();
    error NothingToRecirculate();
    error CirculatorAlreadySet();

    constructor(address initialHolder_) ERC20("Recirculate", "CIRC") Ownable(msg.sender) {
        _mint(initialHolder_, 1_000_000_000 ether);
    }

    function setCirculator(address circulator_) external onlyOwner {
        if (circulator != address(0)) revert CirculatorAlreadySet();
        circulator = circulator_;
        _setStagnant(circulator_, true);
        _setStagnant(address(this), true);
        emit CirculatorSet(circulator_);
    }

    function setStagnant(address account, bool stagnant) external onlyOwner {
        _setStagnant(account, stagnant);
    }

    function _setStagnant(address account, bool stagnant) internal {
        if (isStagnant[account] == stagnant) return;
        _settle(account);
        isStagnant[account] = stagnant;
        uint256 bal = balanceOf(account);
        if (stagnant) {
            excludedSupply += bal;
        } else {
            excludedSupply -= bal;
            rewardDebt[account] = (bal * accTokensPerShare) / 1e18;
        }
        emit StagnantSet(account, stagnant);
    }

    /// @notice Circulator mints reward tokens into this contract and bumps the accumulator.
    function injectFlow(uint256 amount) external {
        if (msg.sender != circulator) revert NotCirculator();
        if (amount == 0) return;

        uint256 eligibleSupply = totalSupply() - excludedSupply;
        if (eligibleSupply == 0) {
            _mint(address(0xdead), amount);
            return;
        }

        _mint(address(this), amount);
        accTokensPerShare += (amount * 1e18) / eligibleSupply;
        emit FlowInjected(amount, accTokensPerShare);
    }

    /// @notice Print flow — uncapped, circulator-only. Goes straight to recipient (no accumulator).
    function printFlow(address recipient, uint256 amount) external {
        if (msg.sender != circulator) revert NotCirculator();
        if (amount == 0) return;
        _mint(recipient, amount);
    }

    function recirculate() external returns (uint256 recirculated) {
        recirculated = pendingFlow(msg.sender);
        if (recirculated == 0) revert NothingToRecirculate();
        rewardDebt[msg.sender] = (balanceOf(msg.sender) * accTokensPerShare) / 1e18;
        totalClaimed[msg.sender] += recirculated;
        _transfer(address(this), msg.sender, recirculated);
        emit Recirculated(msg.sender, recirculated);
    }

    function pendingFlow(address user) public view returns (uint256) {
        if (isStagnant[user]) return 0;
        uint256 bal = balanceOf(user);
        uint256 accrued = (bal * accTokensPerShare) / 1e18;
        if (accrued <= rewardDebt[user]) return 0;
        return accrued - rewardDebt[user];
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) _settle(from);
        if (to != address(0)) _settle(to);

        super._update(from, to, value);

        if (from != address(0) && isStagnant[from]) excludedSupply -= value;
        if (to != address(0) && isStagnant[to]) excludedSupply += value;

        if (from != address(0) && !isStagnant[from]) {
            rewardDebt[from] = (balanceOf(from) * accTokensPerShare) / 1e18;
        }
        if (to != address(0) && !isStagnant[to]) {
            rewardDebt[to] = (balanceOf(to) * accTokensPerShare) / 1e18;
        }
    }

    function _settle(address account) internal {
        if (isStagnant[account]) return;
        uint256 bal = balanceOf(account);
        if (bal == 0) return;
        uint256 accrued = (bal * accTokensPerShare) / 1e18;
        uint256 debt = rewardDebt[account];
        if (accrued <= debt) return;
        uint256 owed = accrued - debt;
        rewardDebt[account] = accrued;
        totalClaimed[account] += owed;
        _transfer(address(this), account, owed);
        emit Recirculated(account, owed);
    }
}
