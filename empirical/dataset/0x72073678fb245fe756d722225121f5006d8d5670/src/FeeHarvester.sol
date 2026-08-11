// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";

import {V4Direct} from "./V4Direct.sol";

/// @title FeeHarvester
/// @notice Permanent owner of the V4 TFLO/native-ETH LP position NFT. `harvest(minOut)` pulls
///         accrued fees only (DECREASE_LIQUIDITY(0)), swaps any TFLO portion into native ETH,
///         and splits 20/80 — team share accrues (`teamOwedEth`, claimable via `claimTeamEth`),
///         treasury share is pushed to `Treasury` immediately.
///
///         v1 design: `harvest` is `onlyOwner` and takes caller-supplied `minOut` for the
///         TFLO→ETH swap. Pull-only team payout means a misconfigured `teamWallet` cannot
///         brick harvest (see ARCHITECTURE.md §9.15). `teamWallet` is owner-rotatable via
///         `setTeamWallet` (single-step) — this widens the §9.16 compromised-owner blast radius
///         (owner can redirect + drain accrued team funds), accepted for redeploy-free rotation.
contract FeeHarvester is V4Direct, Ownable, ReentrancyGuard, IERC721Receiver {
    address public immutable TREASURY;
    /// @dev Team payout target. Owner-rotatable via `setTeamWallet` (not immutable).
    address public teamWallet;
    IPositionManager public immutable POSITION_MANAGER;
    IERC20   public immutable TFLO;

    // V4 PoolKey for TFLO/native-ETH (PoolKey is not a value type so decomposed for immutables).
    address public immutable POOL_CURRENCY0;
    address public immutable POOL_CURRENCY1;
    uint24  public immutable POOL_FEE;
    int24   public immutable POOL_TICK_SPACING;
    address public immutable POOL_HOOKS;
    /// @dev true ⇔ TFLO is currency0; controls swap direction (TFLO→native ETH).
    bool    public immutable TFLO_IS_CURRENCY0;

    /// @dev Position NFT tokenId. Bound once via `bindTokenId` after the NFT is transferred here.
    uint256 public tokenId;

    /// @dev ETH owed to the team wallet (pull pattern).
    uint256 public teamOwedEth;

    uint16 public constant TEAM_SHARE_BPS = 2000;
    uint16 public constant BPS_DENOMINATOR = 10_000;

    event FeesHarvested(uint256 ethTotal, uint256 tfloSwapped, uint256 teamShare, uint256 treasuryShare);
    event TeamClaimed(uint256 amount);
    event TeamWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event TokenIdBound(uint256 tokenId);

    error TokenIdAlreadyBound();
    error TokenIdNotBound();
    error NotTeamWallet();
    error ZeroTeamWallet();
    error EthTransferFailed();
    error InsufficientOutput(uint128 received, uint128 minOut);

    constructor(
        address treasury_,
        address teamWallet_,
        IPoolManager poolManager_,
        IPositionManager positionManager_,
        address tflo_,
        PoolKey memory poolKey_
    ) V4Direct(poolManager_) Ownable(msg.sender) {
        TREASURY = treasury_;
        teamWallet = teamWallet_;
        POSITION_MANAGER = positionManager_;
        TFLO = IERC20(tflo_);

        POOL_CURRENCY0    = Currency.unwrap(poolKey_.currency0);
        POOL_CURRENCY1    = Currency.unwrap(poolKey_.currency1);
        POOL_FEE          = poolKey_.fee;
        POOL_TICK_SPACING = poolKey_.tickSpacing;
        POOL_HOOKS        = address(poolKey_.hooks);
        TFLO_IS_CURRENCY0 = (POOL_CURRENCY0 == tflo_);
    }

    receive() external payable {}

    /// @notice One-shot: bind the LP NFT tokenId. Called by deployer right after `LaunchpadV4.launch`
    ///         transfers the NFT here. Reverts on a second call.
    function bindTokenId(uint256 tokenId_) external onlyOwner {
        if (tokenId != 0) revert TokenIdAlreadyBound();
        tokenId = tokenId_;
        emit TokenIdBound(tokenId_);
    }

    /// @notice Rotate the team payout wallet. Owner-only, single-step. See ARCHITECTURE.md §9.16 —
    ///         this lets a compromised owner redirect and drain accrued team funds; mitigated by
    ///         moving ownership to a multisig immediately post-launch.
    function setTeamWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) revert ZeroTeamWallet();
        emit TeamWalletUpdated(teamWallet, newWallet);
        teamWallet = newWallet;
    }

    /// @notice Collect accrued fees (no principal touched), swap TFLO portion to native ETH, split 20/80.
    /// @param minOutTfloToEth Minimum ETH from the TFLO→ETH swap. Owner-supplied.
    function harvest(uint128 minOutTfloToEth) external onlyOwner nonReentrant {
        if (tokenId == 0) revert TokenIdNotBound();

        uint256 preTflo = TFLO.balanceOf(address(this));
        // Snapshot includes any unclaimed teamOwedEth balance; the delta below captures only
        // the native ETH produced by THIS harvest (TAKE_PAIR fees + the TFLO→ETH swap output).
        uint256 preEth  = address(this).balance;

        // Collect fees only: DECREASE_LIQUIDITY with liquidity=0 + TAKE_PAIR. The non-TFLO side
        // of the pool is native ETH, delivered straight to this contract's balance.
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, uint256(0), uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(_currency0(), _currency1(), address(this));

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        uint256 tfloCollected = TFLO.balanceOf(address(this)) - preTflo;

        // Swap collected TFLO → native ETH via V4 (same pool); output lands in this balance.
        if (tfloCollected > 0) {
            _swapTfloForEth(tfloCollected, minOutTfloToEth);
        }

        uint256 ethTotal = address(this).balance - preEth;
        uint256 teamShare = (ethTotal * TEAM_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 treasuryShare = ethTotal - teamShare;

        teamOwedEth += teamShare;

        if (treasuryShare > 0) {
            (bool ok,) = TREASURY.call{value: treasuryShare}("");
            if (!ok) revert EthTransferFailed();
        }

        emit FeesHarvested(ethTotal, tfloCollected, teamShare, treasuryShare);
    }

    function claimTeamEth() external {
        if (msg.sender != teamWallet) revert NotTeamWallet();
        uint256 amount = teamOwedEth;
        teamOwedEth = 0;
        (bool ok,) = teamWallet.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit TeamClaimed(amount);
    }

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // TEST-ONLY — violates ARCHITECTURE.md §9.2 (LP NFT / principal non-extractable).
    // MUST NOT ship to mainnet. Recovers ETH that accumulates as LP *principal* (e.g. from the
    // buyback buying & burning TFLO) during the smoke test, which `harvest()` deliberately cannot
    // reach. Decreases `liquidity` from the bound position and sends both currencies (native ETH
    // + TFLO) to `to`. `liquidity` is read off-chain (V4 PositionManager/StateView).
    // ─────────────────────────────────────────────────────────────────────────────────────────
    event EmergencyLiquidityWithdrawn(uint128 liquidity, address indexed to);

    function emergencyWithdrawLiquidity(uint128 liquidity, address to) external onlyOwner nonReentrant {
        if (tokenId == 0) revert TokenIdNotBound();

        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, uint256(liquidity), uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(_currency0(), _currency1(), to);

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        emit EmergencyLiquidityWithdrawn(liquidity, to);
    }

    // ── Internal ───────────────────────────────────────────────────────────────────────────────

    function _swapTfloForEth(uint256 amount, uint128 minOut) internal returns (uint256 ethReceived) {
        // V4Direct delivers the native-ETH output to this contract (via receive()).
        // zeroForOne = TFLO is currency0.
        uint128 received = _swapV4ExactIn(_key(), TFLO_IS_CURRENCY0, uint128(amount));
        if (received < minOut) revert InsufficientOutput(received, minOut);
        ethReceived = uint256(received);
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: _currency0(),
            currency1: _currency1(),
            fee: POOL_FEE,
            tickSpacing: POOL_TICK_SPACING,
            hooks: IHooks(POOL_HOOKS)
        });
    }

    function _currency0() internal view returns (Currency) {
        return Currency.wrap(POOL_CURRENCY0);
    }

    function _currency1() internal view returns (Currency) {
        return Currency.wrap(POOL_CURRENCY1);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
