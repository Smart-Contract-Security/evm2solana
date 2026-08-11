// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVault} from "./interfaces/IVault.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {Errors} from "./libs/Errors.sol";

/// @notice Single-asset vault. Holds one ERC20, mints internal non-transferable
///         shares, tracks LP claims, and serves the Router via pullTo.
contract Vault is IVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable override asset;
    uint8 public immutable override decimals;
    uint256 private immutable _unit; // 10**decimals

    IAccessController public immutable access;
    IRewardsDistributor public immutable rewards;

    uint256 public override totalSharesX18;
    uint256 public override totalLpClaims;
    mapping(address => uint256) public override userSharesX18;

    /// @notice Hard cap on total LP-deposited principal (in token native units).
    ///         Pre-audit safety rail. ParamManager (timelock) can raise.
    uint256 public depositCap;

    event DepositCapUpdated(uint256 newCap);

    modifier onlyRouter() {
        if (!access.hasRole(access.ROUTER_ROLE(), msg.sender)) revert Errors.OnlyRouter();
        _;
    }

    modifier onlyTreasury() {
        if (!access.hasRole(access.TREASURY_MANAGER_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyParam() {
        if (!access.hasRole(access.PARAM_MANAGER_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    /// @notice Raise or lower the deposit cap. Only ParamManager (timelock).
    function setDepositCap(uint256 newCap) external onlyParam {
        depositCap = newCap;
        emit DepositCapUpdated(newCap);
    }

    constructor(address asset_, uint8 decimals_, address access_, address rewards_) {
        if (asset_ == address(0) || access_ == address(0) || rewards_ == address(0)) revert Errors.ZeroAddress();
        asset = asset_;
        decimals = decimals_;
        _unit = 10 ** decimals_;
        access = IAccessController(access_);
        rewards = IRewardsDistributor(rewards_);
    }

    /* ------------------------------ views ----------------------------- */

    function assetBalance() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function protocolInventory() external view returns (uint256) {
        uint256 b = assetBalance();
        return b > totalLpClaims ? b - totalLpClaims : 0;
    }

    /* --------------------------- LP actions --------------------------- */

    function deposit(uint256 amount, address receiver) external nonReentrant returns (uint256 sharesMinted) {
        if (access.assetPaused(asset, IAccessController.PauseScope.Deposits)) revert Errors.DepositsPaused();
        if (amount == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();
        // TVL cap (pre-audit safety rail). Set to 0 to disable the cap entirely.
        if (depositCap != 0 && totalLpClaims + amount > depositCap) revert Errors.DepositCapExceeded();

        // 1. Settle pending rewards for receiver
        rewards.settle(receiver, address(this));

        // 2. Transfer asset in
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // 3. Mint shares (1e18 normalized)
        sharesMinted = (amount * 1e18) / _unit;
        if (sharesMinted == 0) revert Errors.ZeroAmount();

        totalSharesX18 += sharesMinted;
        userSharesX18[receiver] += sharesMinted;

        // 4. Increase claims
        totalLpClaims += amount;

        // 5. Sync reward debt to new share count (no pending credit)
        rewards.syncDebt(receiver, address(this));

        emit Deposit(msg.sender, receiver, amount, sharesMinted);
    }

    function withdraw(uint256 shares, address receiver) external nonReentrant returns (uint256 amountOut) {
        if (access.assetPaused(asset, IAccessController.PauseScope.Withdrawals)) revert Errors.WithdrawalsPaused();
        if (shares == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (userSharesX18[msg.sender] < shares) revert Errors.InsufficientShares();

        // 1. Settle pending rewards
        rewards.settle(msg.sender, address(this));

        // 2. Convert shares -> amount
        amountOut = (shares * _unit) / 1e18;
        if (amountOut == 0) revert Errors.ZeroAmount();
        if (assetBalance() < amountOut) revert Errors.InsufficientLiquidity();

        // 3. Burn shares + reduce claims
        userSharesX18[msg.sender] -= shares;
        totalSharesX18 -= shares;
        totalLpClaims -= amountOut;

        // 4. Sync reward debt with new shares
        rewards.syncDebt(msg.sender, address(this));

        // 5. Transfer out
        IERC20(asset).safeTransfer(receiver, amountOut);

        emit Withdraw(msg.sender, receiver, amountOut, shares);
    }

    /* --------------------------- router ops --------------------------- */

    /// @notice Send `amount` of underlying to `receiver`. Router-only. Does NOT touch lpClaims.
    function pullTo(address receiver, uint256 amount) external onlyRouter {
        if (amount == 0) return;
        IERC20(asset).safeTransfer(receiver, amount);
    }

    /* ------------------------- treasury ops -------------------------- */

    function seedInventory(uint256 amount) external onlyTreasury nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit InventorySeeded(amount);
    }

    function withdrawInventory(uint256 amount, address receiver) external onlyTreasury nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();
        uint256 bal = assetBalance();
        // Treasury may only pull true excess
        if (bal < totalLpClaims + amount) revert Errors.InsufficientExcess();
        IERC20(asset).safeTransfer(receiver, amount);
        emit InventoryWithdrawn(receiver, amount);
    }
}
