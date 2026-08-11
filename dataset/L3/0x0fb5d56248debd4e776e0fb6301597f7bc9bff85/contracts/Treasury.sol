// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAccessController} from "./interfaces/IAccessController.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IVault} from "./interfaces/IVault.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {Errors} from "./libs/Errors.sol";

/// @notice Holds protocol fees and runs the $HOUSE buyback-and-burn engine.
///
/// Accounting:
///   - Stablecoins arrive here from Router via receiveProtocolFee().
///   - On arrival, a configurable `buybackBps` of the inbound amount is
///     earmarked for buyback (tracked in `pendingBuyback[token]`).
///   - The rest stays as operational treasury (treasury manager can withdraw).
///   - executeBuyback() is permissionless: anyone can swap the earmarked
///     stables into $HOUSE via Uniswap V3 and burn the proceeds.
///
/// The buyback execution is *open*. There's no privileged actor — keepers,
/// users, or the team can all trigger it. Slippage and deadline are caller-
/// supplied so a stale MEV bot can't grief the buyback into a bad fill.
contract Treasury is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOM = 10_000;

    IAccessController public immutable access;
    IAssetRegistry public immutable registry;

    // ------------------- buyback config -------------------
    address public houseToken;         // $HOUSE
    ISwapRouter public swapRouter;     // Uniswap V3 SwapRouter02

    /// @notice Of every incoming protocol-fee unit, this many bps go to buyback.
    ///         Default 10_000 (100%): all treasury revenue is burned.
    uint16 public buybackBps = 10_000;

    /// @notice Encoded Uniswap V3 path from stable -> HOUSE for each input stable.
    mapping(address => bytes) public buybackPath;

    /// @notice Stablecoin amount earmarked for buyback. Until executeBuyback()
    ///         drains this, the tokens are still physically held by Treasury.
    mapping(address => uint256) public pendingBuyback;

    /// @notice Cumulative HOUSE burned. View-only stat.
    uint256 public totalHouseBurned;

    // ------------------- events -------------------
    event ProtocolFeeReceived(address indexed token, uint256 amount, uint256 toBuyback, address from);
    event BuybackExecuted(address indexed stable, uint256 stableIn, uint256 houseBurned, address indexed caller);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event InventorySeeded(address indexed vault, uint256 amount);
    event InventoryPulled(address indexed vault, uint256 amount);
    event BuybackBpsUpdated(uint16 newBps);
    event BuybackPathUpdated(address indexed stable, bytes path);
    event SwapRouterUpdated(address newRouter);
    event HouseTokenSet(address house);

    modifier onlyTreasury() {
        if (!access.hasRole(access.TREASURY_MANAGER_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyParam() {
        if (!access.hasRole(access.PARAM_MANAGER_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyRouter() {
        if (!access.hasRole(access.ROUTER_ROLE(), msg.sender)) revert Errors.OnlyRouter();
        _;
    }

    constructor(address access_, address registry_) {
        if (access_ == address(0) || registry_ == address(0)) revert Errors.ZeroAddress();
        access = IAccessController(access_);
        registry = IAssetRegistry(registry_);
    }

    // ===================================================================
    //   ADMIN / PARAM
    // ===================================================================

    /// @notice One-time setter for the $HOUSE token. ParamManager only.
    function setHouseToken(address house) external onlyParam {
        if (house == address(0)) revert Errors.ZeroAddress();
        if (houseToken != address(0)) revert Errors.InvalidParam(); // immutable after first set
        houseToken = house;
        emit HouseTokenSet(house);
    }

    function setSwapRouter(address router) external onlyParam {
        if (router == address(0)) revert Errors.ZeroAddress();
        swapRouter = ISwapRouter(router);
        emit SwapRouterUpdated(router);
    }

    function setBuybackBps(uint16 newBps) external onlyParam {
        if (newBps > BPS_DENOM) revert Errors.InvalidParam();
        buybackBps = newBps;
        emit BuybackBpsUpdated(newBps);
    }

    function setBuybackPath(address stable, bytes calldata path) external onlyParam {
        if (stable == address(0)) revert Errors.ZeroAddress();
        if (path.length == 0) revert Errors.InvalidParam();
        buybackPath[stable] = path;
        emit BuybackPathUpdated(stable, path);
    }

    // ===================================================================
    //   FEE INTAKE — called by Router
    // ===================================================================

    function receiveProtocolFee(address token, uint256 amount, address from) external onlyRouter {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(from, address(this), amount);
        uint256 toBuyback = (amount * buybackBps) / BPS_DENOM;
        if (toBuyback > 0) pendingBuyback[token] += toBuyback;
        emit ProtocolFeeReceived(token, amount, toBuyback, from);
    }

    // ===================================================================
    //   BUYBACK + BURN — permissionless
    // ===================================================================

    /// @notice Swap the entire pendingBuyback balance of `stable` for $HOUSE
    ///         and burn it. Anyone can call.
    /// @param  stable           the stablecoin to spend
    /// @param  amountIn         how much to spend (0 = all pending)
    /// @param  minHouseOut      slippage floor
    function executeBuyback(address stable, uint256 amountIn, uint256 minHouseOut)
        external
        nonReentrant
        returns (uint256 houseBurned)
    {
        if (houseToken == address(0) || address(swapRouter) == address(0)) revert Errors.InvalidParam();
        bytes memory path = buybackPath[stable];
        if (path.length == 0) revert Errors.InvalidParam();

        uint256 pending = pendingBuyback[stable];
        if (pending == 0) revert Errors.ZeroAmount();
        if (amountIn == 0 || amountIn > pending) amountIn = pending;

        // Decrement before external call (CEI)
        pendingBuyback[stable] = pending - amountIn;

        // Approve + swap
        IERC20(stable).forceApprove(address(swapRouter), amountIn);
        houseBurned = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minHouseOut
            })
        );

        if (houseBurned > 0) {
            ERC20Burnable(houseToken).burn(houseBurned);
            totalHouseBurned += houseBurned;
        }
        emit BuybackExecuted(stable, amountIn, houseBurned, msg.sender);
    }

    // ===================================================================
    //   OPS TREASURY (non-buyback portion)
    // ===================================================================

    /// @notice Withdraw raw treasury balance to a recipient. Cannot touch the
    ///         pendingBuyback portion — that's earmarked for the burn engine.
    function withdraw(address token, address to, uint256 amount) external onlyTreasury nonReentrant {
        if (to == address(0)) revert Errors.ZeroAddress();
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 free = bal > pendingBuyback[token] ? bal - pendingBuyback[token] : 0;
        if (amount > free) revert Errors.InsufficientExcess();
        IERC20(token).safeTransfer(to, amount);
        emit FundsWithdrawn(token, to, amount);
    }

    // ===================================================================
    //   VAULT INVENTORY OPS
    // ===================================================================

    function seedVaultInventory(address vault, uint256 amount) external onlyTreasury nonReentrant {
        IVault v = IVault(vault);
        address asset = v.asset();
        // Don't seed from earmarked-burn pile
        uint256 bal = IERC20(asset).balanceOf(address(this));
        uint256 free = bal > pendingBuyback[asset] ? bal - pendingBuyback[asset] : 0;
        if (amount > free) revert Errors.InsufficientExcess();
        IERC20(asset).approve(vault, amount);
        v.seedInventory(amount);
        emit InventorySeeded(vault, amount);
    }

    function pullVaultInventory(address vault, uint256 amount) external onlyTreasury nonReentrant {
        IVault(vault).withdrawInventory(amount, address(this));
        emit InventoryPulled(vault, amount);
    }

    // ===================================================================
    //   VIEWS
    // ===================================================================

    function balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function freeBalance(address token) external view returns (uint256) {
        uint256 bal = IERC20(token).balanceOf(address(this));
        return bal > pendingBuyback[token] ? bal - pendingBuyback[token] : 0;
    }
}
