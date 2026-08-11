// SPDX-License-Identifier: MIT

/*
   $LULL · Lull Protocol

   → site      https://earnlull.xyz/
   → x         https://x.com/LullProtocol

   The first universal earnings layer. Turn anything lull - a GPU, an
   agent, a data feed, spare compute - into a paid API endpoint.
*/

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply ERC20 with a self-expiring launch cap. The cap only
///         constrains BUYS (tokens leaving the Uniswap V4 pool to a fresh
///         buyer); sells and normal transfers are never restricted. The window
///         arms on the first buy and lifts automatically after a fixed number
///         of blocks (or earlier if the owner lifts it). No mint, no burn, no
///         pause, no fee — caps only.
contract LullProtocol is ERC20 {
    /// @dev build
    function zae71bac8() external pure returns (uint256) { return 872696530672; }

    bytes32 public constant VERSION =
        0xae71bac858e7232587fd8c0f1c0cbeaecc1a862744e0e56f6d040168d5df16f0;

    // Uniswap V4 PoolManager (Ethereum mainnet). A buy = transfer FROM here.
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    string private _n;
    string private _s;

    address  public owner;                     // mutable — renounced (→0x0) right after launch
    uint256  public immutable capSupply;       // supply snapshot the bps caps apply to
    uint16   public immutable maxTxBps;        // per-buy cap vs supply (0 = off)
    uint16   public immutable maxWalletBps;    // resulting-balance cap vs supply (0 = off)
    uint32   public immutable limitsBlocks;    // window length in blocks (0 = no cap ever)

    uint64   public limitsLaunchBlock;         // armed on first buy
    bool     public limitsLifted;              // one-way (owner) early lift
    mapping(address => bool) public isExempt;  // routers/CEX/etc — owner-managed

    error ZeroAddress();
    error NotOwner();
    error BpsTooHigh();
    error MaxTxExceeded();
    error MaxWalletExceeded();

    event LimitsArmed(uint64 liftBlock);
    event LimitsLifted();
    event ExemptSet(address indexed account, bool exempt);
    // Standard OZ-style ownership event so Etherscan + scanners recognise the renounce.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        string memory n_,
        string memory s_,
        uint256 supply_,
        address mintTo_,
        uint16  maxTxBps_,
        uint16  maxWalletBps_,
        uint32  limitsBlocks_
    ) ERC20("", "") {
        if (mintTo_ == address(0)) revert ZeroAddress();
        if (maxTxBps_ > 10_000 || maxWalletBps_ > 10_000) revert BpsTooHigh();
        _n = n_;
        _s = s_;
        owner        = mintTo_;
        capSupply    = supply_;
        maxTxBps     = maxTxBps_;
        maxWalletBps = maxWalletBps_;
        limitsBlocks = limitsBlocks_;
        isExempt[mintTo_]      = true;   // deployer seeds LP / moves freely
        isExempt[POOL_MANAGER] = true;   // pool itself never capped as recipient
        _mint(mintTo_, supply_);
        emit OwnershipTransferred(address(0), mintTo_);
    }

    function name() public view override returns (string memory) { return _n; }
    function symbol() public view override returns (string memory) { return _s; }

    function setExempt(address a, bool e) external {
        if (msg.sender != owner) revert NotOwner();
        isExempt[a] = e;
        emit ExemptSet(a, e);
    }

    function liftLimitsNow() external {
        if (msg.sender != owner) revert NotOwner();
        limitsLifted = true;
        emit LimitsLifted();
    }

    /// @notice Permanently give up ownership (owner → address(0)). After this,
    ///         setExempt/liftLimitsNow can never be called again. Standard
    ///         renounce — scanners read owner()==0 / the OwnershipTransferred
    ///         event and mark the token renounced. The launcher calls this
    ///         right after trading opens; the buy cap still self-expires by
    ///         block schedule regardless.
    function renounceOwnership() external {
        if (msg.sender != owner) revert NotOwner();
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /// @return active whether the buy cap is currently enforced
    function limitsActive() public view returns (bool active) {
        if (limitsLifted || limitsBlocks == 0) return false;
        uint64 lb = limitsLaunchBlock;
        if (lb == 0) return true;                       // armed on first buy
        return block.number < uint256(lb) + limitsBlocks;
    }

    // OZ v5 transfer hook. Enforce the cap on BUYS only (from == PoolManager).
    function _update(address from, address to, uint256 value) internal override {
        if (from == POOL_MANAGER && to != address(0) && !isExempt[to]) {
            if (!limitsLifted && limitsBlocks != 0) {
                if (limitsLaunchBlock == 0) {
                    limitsLaunchBlock = uint64(block.number);
                    emit LimitsArmed(uint64(block.number) + limitsBlocks);
                }
                if (block.number < uint256(limitsLaunchBlock) + limitsBlocks) {
                    if (maxTxBps != 0 && value > (capSupply * maxTxBps) / 10_000) {
                        revert MaxTxExceeded();
                    }
                    if (maxWalletBps != 0 &&
                        balanceOf(to) + value > (capSupply * maxWalletBps) / 10_000) {
                        revert MaxWalletExceeded();
                    }
                }
            }
        }
        super._update(from, to, value);
    }
}
