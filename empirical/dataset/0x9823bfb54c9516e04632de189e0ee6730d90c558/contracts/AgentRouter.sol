// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICoboFundToken} from "./interfaces/ICoboFundToken.sol";

/// @title AgentRouter
/// @notice Retail / permissionless entry for XAUT -> XAUE mint and async redemption claims; product name "Agent-Router".
/// @dev XAUERouter-style flow: pulls `asset` from user, calls `fundToken.mint`, returns XAUE to user. `fundToken` is the Cobo-style share contract (`CoboFundToken` / mock).
contract AgentRouter is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for ICoboFundToken;

    bytes32 public constant BLACKLIST_ADMIN_ROLE = keccak256("BLACKLIST_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public asset;
    ICoboFundToken public fundToken;

    uint256 public nextRouterReqId;
    mapping(uint256 => RouterRedemption) public routerRedemptions;
    mapping(address => bool) public blacklist;

    enum RouterRedemptionStatus {
        Pending,
        Claimable,
        Rejected,
        Claimed
    }

    struct RouterRedemption {
        uint256 id;
        address user;
        uint256 navReqId;
        uint256 xaueAmount;
        uint256 requestedAt;
        bool xautClaimed;
        bool rejectedSharesClaimed;
    }

    event MintRouted(address indexed user, uint256 xautAmount, uint256 xaueAmount);
    event RedemptionRequestedViaRouter(
        uint256 indexed routerReqId,
        uint256 indexed navReqId,
        address indexed user,
        uint256 xaueAmount
    );
    event XautClaimed(uint256 indexed routerReqId, address indexed user, uint256 xautAmount);
    event RejectedSharesClaimed(uint256 indexed routerReqId, address indexed user, uint256 xaueAmount);
    event BlacklistUpdated(address indexed account, bool blocked);
    event RescueToken(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error Blacklisted();
    error SlippageExceeded();
    error RescueRequiresPause();
    error UnknownRequest();
    error NotRequestOwner();
    error AlreadyClaimed();
    error NotClaimable();
    error NotRejected();
    error InsufficientAsset();
    error InsufficientShares();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @param defaultAdmin_ receives `DEFAULT_ADMIN_ROLE` (role grants, upgrades).
    /// @param blacklistAdmin_ receives `BLACKLIST_ADMIN_ROLE` (`setBlacklist`); may equal `defaultAdmin_` for single-key deploys.
    /// @param pauser_ receives `PAUSER_ROLE` (`pause` / `unpause`); may equal `defaultAdmin_` for single-key deploys.
    function initialize(
        address asset_,
        address fundToken_,
        address defaultAdmin_,
        address blacklistAdmin_,
        address pauser_
    ) external initializer {
        if (
            asset_ == address(0) || fundToken_ == address(0) || defaultAdmin_ == address(0) || blacklistAdmin_ == address(0)
                || pauser_ == address(0)
        ) {
            revert ZeroAddress();
        }

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin_);
        _grantRole(BLACKLIST_ADMIN_ROLE, blacklistAdmin_);
        _grantRole(PAUSER_ROLE, pauser_);

        asset = IERC20(asset_);
        fundToken = ICoboFundToken(fundToken_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setBlacklist(address account, bool blocked) external onlyRole(BLACKLIST_ADMIN_ROLE) {
        blacklist[account] = blocked;
        emit BlacklistUpdated(account, blocked);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Pull XAUT from user, mint XAUE via fund, transfer XAUE to user.
    /// @param minXaueOut Minimum XAUE shares received from `fundToken.mint` (slippage guard vs oracle/NAV at execution).
    function mint(uint256 xautAmount, uint256 minXaueOut) external whenNotPaused nonReentrant {
        if (blacklist[msg.sender]) revert Blacklisted();
        if (xautAmount == 0) revert ZeroAmount();

        asset.safeTransferFrom(msg.sender, address(this), xautAmount);
        asset.safeIncreaseAllowance(address(fundToken), xautAmount);

        uint256 xaueAmount = fundToken.mint(xautAmount);

        asset.forceApprove(address(fundToken), 0);

        if (xaueAmount < minXaueOut) revert SlippageExceeded();

        fundToken.safeTransfer(msg.sender, xaueAmount);
        emit MintRouted(msg.sender, xautAmount, xaueAmount);
    }

    /// @notice Pull XAUE from user, open redemption on fund, record `routerReqId`.
    /// @param minXautOut Minimum XAUT amount recorded on the fund redemption request (NAV at request time).
    function requestRedeem(uint256 xaueAmount, uint256 minXautOut)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 routerReqId)
    {
        if (blacklist[msg.sender]) revert Blacklisted();
        if (xaueAmount == 0) revert ZeroAmount();

        fundToken.safeTransferFrom(msg.sender, address(this), xaueAmount);

        uint256 navReqId = fundToken.requestRedemption(xaueAmount);

        (, , uint256 assetAmount, , , ) = fundToken.redemptions(navReqId);
        if (assetAmount < minXautOut) revert SlippageExceeded();

        routerReqId = nextRouterReqId++;
        routerRedemptions[routerReqId] = RouterRedemption({
            id: routerReqId,
            user: msg.sender,
            navReqId: navReqId,
            xaueAmount: xaueAmount,
            requestedAt: block.timestamp,
            xautClaimed: false,
            rejectedSharesClaimed: false
        });

        emit RedemptionRequestedViaRouter(routerReqId, navReqId, msg.sender, xaueAmount);
    }

    function getRouterRedemptionStatus(uint256 routerReqId) public view returns (RouterRedemptionStatus) {
        RouterRedemption memory r = routerRedemptions[routerReqId];
        if (r.user == address(0)) revert UnknownRequest();

        (, , , , , ICoboFundToken.RedemptionStatus st) = fundToken.redemptions(r.navReqId);

        if (st == ICoboFundToken.RedemptionStatus.Pending) {
            return RouterRedemptionStatus.Pending;
        }
        if (st == ICoboFundToken.RedemptionStatus.Executed) {
            return r.xautClaimed ? RouterRedemptionStatus.Claimed : RouterRedemptionStatus.Claimable;
        }
        return r.rejectedSharesClaimed ? RouterRedemptionStatus.Claimed : RouterRedemptionStatus.Rejected;
    }

    function getUnderlyingRequestId(uint256 routerReqId) external view returns (uint256) {
        RouterRedemption memory r = routerRedemptions[routerReqId];
        if (r.user == address(0)) revert UnknownRequest();
        return r.navReqId;
    }

    /// @notice Recover ERC20 mistakenly sent to the router. `asset` / `fundToken` require pause.
    function rescueERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if ((token == address(asset) || token == address(fundToken)) && !paused()) {
            revert RescueRequiresPause();
        }
        IERC20(token).safeTransfer(to, amount);
        emit RescueToken(token, to, amount);
    }

    /// @notice After fund redemption is executed, transfer XAUT payout from Router to user.
    /// @dev Blacklist and pause do not apply; users may claim existing requests (see Issue-2 policy).
    function claimXaut(uint256 routerReqId) external nonReentrant {
        RouterRedemption storage r = routerRedemptions[routerReqId];
        if (r.user != msg.sender) revert NotRequestOwner();
        if (r.xautClaimed) revert AlreadyClaimed();

        (, , uint256 assetAmount, , , ICoboFundToken.RedemptionStatus st) = fundToken.redemptions(r.navReqId);
        if (st != ICoboFundToken.RedemptionStatus.Executed) revert NotClaimable();
        if (asset.balanceOf(address(this)) < assetAmount) revert InsufficientAsset();

        r.xautClaimed = true;
        asset.safeTransfer(msg.sender, assetAmount);
        emit XautClaimed(routerReqId, msg.sender, assetAmount);
    }

    /// @notice After fund redemption is rejected, return XAUE shares from Router to user.
    /// @dev Blacklist and pause do not apply; users may claim existing requests (see Issue-2 policy).
    function claimRejectedShares(uint256 routerReqId) external nonReentrant {
        RouterRedemption storage r = routerRedemptions[routerReqId];
        if (r.user != msg.sender) revert NotRequestOwner();
        if (r.rejectedSharesClaimed) revert AlreadyClaimed();

        (, , , uint256 shareAmount, , ICoboFundToken.RedemptionStatus st) = fundToken.redemptions(r.navReqId);
        if (st != ICoboFundToken.RedemptionStatus.Rejected) revert NotRejected();
        if (fundToken.balanceOf(address(this)) < shareAmount) revert InsufficientShares();

        r.rejectedSharesClaimed = true;
        fundToken.safeTransfer(msg.sender, shareAmount);
        emit RejectedSharesClaimed(routerReqId, msg.sender, shareAmount);
    }

    uint256[45] private __gap;
}
