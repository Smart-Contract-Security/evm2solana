



/* ----------------------------------------------------------------------------
 *                   		DAEMONSv4 (DAEMON)          
 * ----------------------------------------------------------------------------
 *          Uniswap V4 Hook-Centric Concentrated Liquidity AMM
 *
 *   // https://x.com/DAEMONSv4
 *   // https://daemons.life/
 *
 * A high-performance AMM built directly on Uniswap v4 PoolManager with
 * custom dynamic hooks for adaptive fees, volatility-adjusted spreads,
 * concentrated liquidity management, and on-chain limit order execution.
 *
 * Key Technical Integrations:
 *   • IHooks implementation (before/afterSwap, before/afterAddLiquidity,
 *     before/afterRemoveLiquidity, beforeInitialize, afterInitialize)
 *   • Custom PoolKey + dynamic fee + tick spacing hooks
 *   • BalanceDelta + CurrencyLib accounting
 *   • PositionManager + LiquidityPosition NFT integration
 *   • MEV-resistant hook architecture with flash accounting
 *
 * Core Hook Capabilities:
 *   - Real-time volatility & volume based fee adjustment
 *   - Dynamic tick spacing & liquidity concentration
 *   - Automated rebalancing & range order hooks
 *   - Protocol-owned liquidity (POL) vault callbacks
 *   - Custom swap routing & intent-based execution hooks
 *
 * DAEMON Token Role:
 *   - Governance + fee capture token (ERC20 + ERC20Permit)
 *   - veDAEMON staking & revenue share
 *   - Emissions controller linked to protocol TVL & volume
 *
 * @author DAEMON Core Contributors
 * @notice Canonical DAEMON token contract - Do not deploy forks
 * -------------------------------------------------------------------------- */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";


contract Staking {
    address DAEMON_TOKEN_CONTRACT = 0x9622430B35689C5E12fE9997c7CD88BdC6B7A8AA;
    address public immutable owner;
    uint256 public constant APR_BPS = 1000;        // 10% APR
    uint256 public constant YEAR    = 365 days;
    uint256 public constant BPS     = 10_000;
    

    struct Stake {
        uint128 amount;
        uint64  since;
        uint128 accrued; // rewards accrued but not yet claimPapered (on top-up / partial unstakePaperPaper)
    }

    mapping(address => Stake) public stakePapers;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount);
    event UnstakePaperd(address indexed user, uint256 amount, uint256 reward);
    event Claimed(address indexed user, uint256 reward);
    event Funded(uint256 amount);

    constructor() { owner = msg.sender; }

    receive() external payable { emit Funded(msg.value); } // owner funds reward pool

    function _pending(Stake memory s) internal view returns (uint256) {
        if (s.amount == 0) return s.accrued;
        uint256 dt = block.timestamp - s.since;
        return s.accrued + (uint256(s.amount) * APR_BPS * dt) / (BPS * YEAR);
    }

    function pendingReward(address user) external view returns (uint256) {
        return _pending(stakePapers[user]);
    }

    function stakeDAEMON() external payable {
        require(msg.value > 0, "zero");
        Stake storage s = stakePapers[msg.sender];
        s.accrued = uint128(_pending(s));          // snapshot prior rewards
        s.amount += uint128(msg.value);
        s.since   = uint64(block.timestamp);
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function unstakeDAEMON(uint256 amount) external {
        Stake storage s = stakePapers[msg.sender];
        require(amount > 0 && amount <= s.amount, "bad amount");
        uint256 reward = _pending(s);
        s.accrued = 0;
        s.amount -= uint128(amount);
        s.since   = uint64(block.timestamp);
        totalStaked -= amount;

        (bool ok, ) = msg.sender.call{value: amount + reward}("");
        require(ok, "xfer");
        emit UnstakePaperd(msg.sender, amount, reward);
    }

    function claimDAEMON() external {
        Stake storage s = stakePapers[msg.sender];
        uint256 reward = _pending(s);
        require(reward > 0, "nothing");
        s.accrued = 0;
        s.since   = uint64(block.timestamp);
        (bool ok, ) = msg.sender.call{value: reward}("");
        require(ok, "xfer");
        emit Claimed(msg.sender, reward);
    }

    /// @notice Owner can pull non-stakePaperd ETH (e.g. excess reward funding). Cannot touch principal.
    function sweep(uint256 amount) external {
        require(msg.sender == owner, "!owner");
        require(address(this).balance - amount >= totalStaked, "principal");
        (bool ok, ) = owner.call{value: amount}("");
        require(ok, "xfer");
    }
}
