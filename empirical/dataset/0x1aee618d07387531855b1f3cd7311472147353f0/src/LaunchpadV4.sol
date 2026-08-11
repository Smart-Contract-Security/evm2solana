// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {Addresses} from "./Addresses.sol";

interface IPermit2Approve {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// @title LaunchpadV4
/// @notice One-shot deployer-only launch of the V4 TFLO/native-ETH pool with 5% fee and no oracle
///         hook. Mints a **one-sided** LP position (TFLO only, no ETH) on caller-supplied ticks,
///         transfers the NFT to `FeeHarvester`, then disables itself. Reverts on second call.
///         Mirrors the one-sided launch pattern from
///         `../tokenstrategy-sol/script/utils/V4Launcher.s.sol`.
contract LaunchpadV4 is IERC721Receiver {
    using SafeERC20 for IERC20;

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @dev Native ETH is the pool counterparty (currency address 0), not WETH.
    address internal constant NATIVE_ETH = address(0);

    address public immutable DEPLOYER;
    IPoolManager public immutable POOL_MANAGER;
    IPositionManager public immutable POSITION_MANAGER;
    IERC20 public immutable TFLO;
    address public immutable FEE_HARVESTER;

    // Constants per ARCHITECTURE.md §3.1 — sourced from Addresses.sol (single source of truth).
    uint24 public constant POOL_FEE = Addresses.TFLO_POOL_FEE;       // 5%
    int24  public constant TICK_SPACING = Addresses.TFLO_TICK_SPACING; // 200

    bool public launched;
    uint256 public mintedTokenId;

    error NotDeployer();
    error AlreadyLaunched();
    error NoPositionMinted();
    error NotOneSided();

    event Launched(
        uint256 indexed tokenId,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 tfloAmount,
        uint128 liquidity
    );

    constructor(
        address tflo,
        IPoolManager poolManager_,
        IPositionManager positionManager_,
        address feeHarvester_
    ) {
        DEPLOYER = msg.sender;
        TFLO = IERC20(tflo);
        POOL_MANAGER = poolManager_;
        POSITION_MANAGER = positionManager_;
        FEE_HARVESTER = feeHarvester_;
    }

    /// @notice One-shot one-sided launch. Deployer must approve TFLO to this contract.
    /// @param sqrtPriceX96 Initial pool price. Enforced to sit on the TFLO side of the
    ///                     position's tick range: `<= sqrtPriceAtTick(tickLower)` when TFLO
    ///                     is currency0, or `>= sqrtPriceAtTick(tickUpper)` when TFLO is
    ///                     currency1. Misconfiguration reverts with `NotOneSided` before
    ///                     touching the pool — protects against future supply/mcap changes
    ///                     that could silently produce a two-sided position.
    /// @param tickLower    Lower tick of the LP position (must be aligned to TICK_SPACING).
    /// @param tickUpper    Upper tick of the LP position (must be aligned to TICK_SPACING).
    /// @param tfloAmount   TFLO to seed (full balance is expected: 1e9 * 1e18).
    function launch(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 tfloAmount
    ) external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (launched) revert AlreadyLaunched();
        launched = true;

        // Enforce one-sided invariant: current price must sit on the TFLO side of the
        // tick range, so the position holds zero of the non-TFLO currency at mint time.
        // Native ETH (address 0) always sorts first, so TFLO is currency1 here.
        bool tfloIsToken0 = address(TFLO) < NATIVE_ETH;
        if (tfloIsToken0) {
            if (sqrtPriceX96 > TickMath.getSqrtPriceAtTick(tickLower)) revert NotOneSided();
        } else {
            if (sqrtPriceX96 < TickMath.getSqrtPriceAtTick(tickUpper)) revert NotOneSided();
        }

        TFLO.safeTransferFrom(msg.sender, address(this), tfloAmount);

        // Construct PoolKey with hooks = 0 (no oracle hook in v1 — see ARCHITECTURE.md §1).
        PoolKey memory key = _poolKey();

        POOL_MANAGER.initialize(key, sqrtPriceX96);

        // Approve Permit2 → PositionManager for TFLO only. Native ETH is never pulled
        // (the position is one-sided TFLO, so the ETH amount is zero).
        TFLO.approve(PERMIT2, type(uint256).max);
        IPermit2Approve(PERMIT2).approve(address(TFLO), address(POSITION_MANAGER), type(uint160).max, type(uint48).max);

        uint256 expectedTokenId = POSITION_MANAGER.nextTokenId();

        // amount0Desired / amount1Desired must match PoolKey currency order — TFLO sits in
        // whichever slot corresponds to its address sort vs native ETH. The other slot is zero
        // because the position lives on the TFLO side of current price (enforced above).
        (uint256 amount0Desired, uint256 amount1Desired) = tfloIsToken0
            ? (tfloAmount, uint256(0))
            : (uint256(0), tfloAmount);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            liquidity,
            uint128(amount0Desired),
            uint128(amount1Desired),
            address(this),
            bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        if (IERC721(address(POSITION_MANAGER)).ownerOf(expectedTokenId) != address(this)) {
            revert NoPositionMinted();
        }
        mintedTokenId = expectedTokenId;

        IERC721(address(POSITION_MANAGER)).safeTransferFrom(address(this), FEE_HARVESTER, expectedTokenId);

        emit Launched(expectedTokenId, sqrtPriceX96, tickLower, tickUpper, tfloAmount, liquidity);
    }

    function _poolKey() internal view returns (PoolKey memory key) {
        address tflo = address(TFLO);
        (address c0, address c1) = tflo < NATIVE_ETH ? (tflo, NATIVE_ETH) : (NATIVE_ETH, tflo);
        key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
