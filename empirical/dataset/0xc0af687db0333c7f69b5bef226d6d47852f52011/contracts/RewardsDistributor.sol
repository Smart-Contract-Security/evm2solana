// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Errors} from "./libs/Errors.sol";

/// @notice MasterChef-style per-vault per-token reward indexes. Rewards
///         are paid in the *input* asset of each swap; LPs of the *output*
///         vault accrue them.
contract RewardsDistributor is IRewardsDistributor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant ACC_SCALE = 1e30;

    IAccessController public immutable access;

    // vault => token => accumulator
    mapping(address => mapping(address => uint256)) public accRewardPerShare;
    // user => vault => token => debt
    mapping(address => mapping(address => mapping(address => uint256))) public rewardDebt;
    // user => vault => token => claimable
    mapping(address => mapping(address => mapping(address => uint256))) public claimable;

    // vault => list of known reward tokens
    mapping(address => address[]) private _rewardTokens;
    mapping(address => mapping(address => bool)) private _hasRewardToken;

    modifier onlyRouter() {
        if (!access.hasRole(access.ROUTER_ROLE(), msg.sender)) revert Errors.OnlyRouter();
        _;
    }

    modifier onlyVault(address vault) {
        // Trust the vault to call settle/syncDebt for its own users.
        if (msg.sender != vault) revert Errors.OnlyVault();
        _;
    }

    constructor(address access_) {
        if (access_ == address(0)) revert Errors.ZeroAddress();
        access = IAccessController(access_);
    }

    /* ==================================================================
       ACCRUAL — called by Router
    ================================================================== */

    function accrueReward(address vault, address rewardToken, uint256 amount) external onlyRouter {
        if (amount == 0) return;
        uint256 supply = IVault(vault).totalSharesX18();
        if (supply == 0) revert Errors.InvalidParam(); // router must not send if supply==0

        if (!_hasRewardToken[vault][rewardToken]) {
            _hasRewardToken[vault][rewardToken] = true;
            _rewardTokens[vault].push(rewardToken);
        }
        accRewardPerShare[vault][rewardToken] += (amount * ACC_SCALE) / supply;
        emit RewardAccrued(vault, rewardToken, amount);
    }

    /* ==================================================================
       SETTLEMENT HOOKS — called by Vault
    ================================================================== */

    /// @notice Credit user's pending rewards based on current share balance.
    ///         Called BEFORE a deposit or withdraw.
    function settle(address user, address vault) public onlyVault(vault) {
        _settle(user, vault);
    }

    function settleOne(address user, address vault, address rewardToken) external onlyVault(vault) {
        _settleOne(user, vault, rewardToken);
    }

    /// @notice Reset reward debt to current shares without crediting pending.
    ///         Called by Vault AFTER mutating share balances.
    function syncDebt(address user, address vault) external onlyVault(vault) {
        uint256 shares = IVault(vault).userSharesX18(user);
        address[] memory tokens = _rewardTokens[vault];
        for (uint256 i = 0; i < tokens.length; ++i) {
            rewardDebt[user][vault][tokens[i]] = (shares * accRewardPerShare[vault][tokens[i]]) / ACC_SCALE;
        }
    }

    /// @notice Reset debt after share count changes. Called by vault flows
    ///         externally — currently merged into settle (see Vault).
    function _settle(address user, address vault) internal {
        uint256 shares = IVault(vault).userSharesX18(user);
        address[] memory tokens = _rewardTokens[vault];
        for (uint256 i = 0; i < tokens.length; ++i) {
            _settleTokenWithShares(user, vault, tokens[i], shares);
        }
    }

    function _settleOne(address user, address vault, address token) internal {
        uint256 shares = IVault(vault).userSharesX18(user);
        _settleTokenWithShares(user, vault, token, shares);
    }

    function _settleTokenWithShares(address user, address vault, address token, uint256 shares) internal {
        uint256 acc = accRewardPerShare[vault][token];
        uint256 accrued = (shares * acc) / ACC_SCALE;
        uint256 debt = rewardDebt[user][vault][token];
        if (accrued > debt) {
            claimable[user][vault][token] += (accrued - debt);
        }
        rewardDebt[user][vault][token] = accrued;
    }

    /* ==================================================================
       CLAIMING
    ================================================================== */

    function claimReward(address vault, address rewardToken) public nonReentrant returns (uint256 amt) {
        _settleOne(msg.sender, vault, rewardToken);
        amt = claimable[msg.sender][vault][rewardToken];
        if (amt > 0) {
            claimable[msg.sender][vault][rewardToken] = 0;
            IERC20(rewardToken).safeTransfer(msg.sender, amt);
            emit RewardClaimed(vault, msg.sender, rewardToken, amt);
        }
    }

    function claimAll(address vault) external nonReentrant returns (uint256 total) {
        _settle(msg.sender, vault);
        address[] memory tokens = _rewardTokens[vault];
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amt = claimable[msg.sender][vault][tokens[i]];
            if (amt > 0) {
                claimable[msg.sender][vault][tokens[i]] = 0;
                IERC20(tokens[i]).safeTransfer(msg.sender, amt);
                emit RewardClaimed(vault, msg.sender, tokens[i], amt);
                total += amt;
            }
        }
    }

    /* ==================================================================
       VIEWS
    ================================================================== */

    function pending(address user, address vault, address rewardToken) external view returns (uint256) {
        uint256 shares = IVault(vault).userSharesX18(user);
        uint256 acc = accRewardPerShare[vault][rewardToken];
        uint256 accrued = (shares * acc) / ACC_SCALE;
        uint256 debt = rewardDebt[user][vault][rewardToken];
        uint256 newOwed = accrued > debt ? (accrued - debt) : 0;
        return claimable[user][vault][rewardToken] + newOwed;
    }

    function rewardTokensFor(address vault) external view returns (address[] memory) {
        return _rewardTokens[vault];
    }
}
