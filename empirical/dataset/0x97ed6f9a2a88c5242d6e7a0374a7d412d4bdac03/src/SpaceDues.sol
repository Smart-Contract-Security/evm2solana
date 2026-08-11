// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAzimuth} from "../src/Interfaces/IAzimuth.sol";
import {ISpaceDues} from "../src/Interfaces/ISpaceDues.sol";
import {ISpacePort} from "../src/Interfaces/ISpacePort.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SpaceDues
 * @notice ERC20 prepaid dues layer for SpacePort spaces.
 * @dev SpacePort remains the membership source of truth. This contract only records paid-through
 *      timestamps and claimable dues balances; app-layer access should require both membership
 *      and current dues when terms are active.
 */
contract SpaceDues is ISpaceDues, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidSpacePort();
    error UnauthorizedHubController();
    error UnauthorizedSpaceController();
    error UnauthorizedClaim();
    error SpaceDoesNotExist();
    error SpaceDestroyed();
    error InvalidToken();
    error TokenNotAllowed(address token);
    error InvalidAmount();
    error InvalidPeriod();
    error InvalidPeriods();
    error DuesInactive();
    error NotSpaceMember(uint32 urbitId);
    error PaidThroughOverflow();
    error NothingToClaim();
    error BadTokenTransfer(address token, uint256 expected, uint256 received);

    ISpacePort public immutable spacePort;
    IAzimuth public immutable azimuth;

    mapping(address => bool) public paymentTokenAllowed;
    mapping(bytes32 => Terms) private _terms;
    mapping(bytes32 => mapping(uint32 => uint64)) public paidThrough;
    mapping(bytes32 => mapping(address => uint256)) public claimable;

    constructor(address spacePortAddress) {
        if (spacePortAddress == address(0) || spacePortAddress.code.length == 0) {
            revert InvalidSpacePort();
        }

        spacePort = ISpacePort(spacePortAddress);
        address azimuthAddress = ISpacePort(spacePortAddress).getAzimuth();
        if (azimuthAddress == address(0)) revert InvalidSpacePort();
        azimuth = IAzimuth(azimuthAddress);
    }

    function setPaymentTokenAllowed(address token, bool allowed) external {
        _requireHubController();
        if (token == address(0)) revert InvalidToken();
        paymentTokenAllowed[token] = allowed;
        emit PaymentTokenAllowed(token, allowed);
    }

    function setTerms(bytes32 spaceKey, Terms calldata newTerms) external {
        _requireLiveSpaceController(spaceKey);

        if (newTerms.active) {
            if (newTerms.token == address(0)) revert InvalidToken();
            if (!paymentTokenAllowed[newTerms.token]) revert TokenNotAllowed(newTerms.token);
            if (newTerms.amount == 0) revert InvalidAmount();
            if (newTerms.periodSeconds == 0) revert InvalidPeriod();
        }

        _terms[spaceKey] = newTerms;
        emit TermsUpdated(
            spaceKey,
            newTerms.token,
            newTerms.amount,
            newTerms.periodSeconds,
            newTerms.graceSeconds,
            newTerms.treasury,
            newTerms.active
        );
    }

    /// @notice Narrow setter for the common case where a host only wants to change the price.
    ///         Token, period, grace, treasury, and active flag are untouched. Cheaper than
    ///         re-sending the full Terms struct (~6.5k gas) and makes "host changed the price"
    ///         legible from chain history.
    ///
    ///         Works whether dues are active or not. When inactive, the amount is purely
    ///         informational — `pay()` still reverts and `isPaid()` still returns true for
    ///         everyone — but a host can use it to advertise a planned price during a
    ///         promotional / pre-launch window without actually collecting yet, then flip
    ///         `active` to true via `setTerms` when ready.
    function setAmount(bytes32 spaceKey, uint256 newAmount) external {
        _requireLiveSpaceController(spaceKey);
        if (newAmount == 0) revert InvalidAmount();
        _terms[spaceKey].amount = newAmount;
        emit AmountUpdated(spaceKey, newAmount);
    }

    function pay(bytes32 spaceKey, uint32 urbitId, uint32 periods)
        external
        nonReentrant
        returns (uint64 newPaidThrough)
    {
        if (periods == 0) revert InvalidPeriods();
        _requireLiveSpace(spaceKey);
        if (!spacePort.isMember(spaceKey, urbitId)) revert NotSpaceMember(urbitId);

        Terms memory currentTerms = _terms[spaceKey];
        if (!currentTerms.active) revert DuesInactive();
        if (!paymentTokenAllowed[currentTerms.token]) revert TokenNotAllowed(currentTerms.token);

        uint256 total = currentTerms.amount * uint256(periods);
        IERC20 token = IERC20(currentTerms.token);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), total);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received != total) revert BadTokenTransfer(currentTerms.token, total, received);

        uint64 oldPaidThrough = paidThrough[spaceKey][urbitId];
        uint256 start = oldPaidThrough > block.timestamp ? oldPaidThrough : block.timestamp;
        uint256 end = start + (uint256(periods) * uint256(currentTerms.periodSeconds));
        if (end > type(uint64).max) revert PaidThroughOverflow();

        newPaidThrough = uint64(end);
        paidThrough[spaceKey][urbitId] = newPaidThrough;
        claimable[spaceKey][currentTerms.token] += total;

        emit DuesPaid(spaceKey, urbitId, msg.sender, currentTerms.token, periods, total, newPaidThrough);
    }

    function isPaid(bytes32 spaceKey, uint32 urbitId) public view returns (bool) {
        Terms memory currentTerms = _terms[spaceKey];
        if (!currentTerms.active) return true;

        uint64 paidUntil = paidThrough[spaceKey][urbitId];
        if (paidUntil == 0) return false;

        return uint256(_graceEnds(paidUntil, currentTerms.graceSeconds)) >= block.timestamp;
    }

    function accessStatus(bytes32 spaceKey, uint32 urbitId)
        external
        view
        returns (
            bool spaceExists,
            bool destroyed,
            bool duesActive,
            bool member,
            bool banned,
            bool paid,
            uint64 paidUntil,
            uint64 graceEnds,
            address token,
            uint256 amount,
            uint64 periodSeconds
        )
    {
        spaceExists = spacePort.exists(spaceKey);
        if (spaceExists) {
            destroyed = spacePort.isDestroyed(spaceKey);
            member = spacePort.isMember(spaceKey, urbitId);
            banned = spacePort.isBanned(spaceKey, urbitId);
        }

        Terms memory currentTerms = _terms[spaceKey];
        duesActive = currentTerms.active;
        paidUntil = paidThrough[spaceKey][urbitId];
        graceEnds = _graceEnds(paidUntil, currentTerms.graceSeconds);
        paid = !duesActive || (paidUntil != 0 && uint256(graceEnds) >= block.timestamp);
        token = currentTerms.token;
        amount = currentTerms.amount;
        periodSeconds = currentTerms.periodSeconds;
    }

    function claim(bytes32 spaceKey, address token) external nonReentrant returns (uint256 amount) {
        uint32 ownerId = _requireSpaceExists(spaceKey);
        Terms memory currentTerms = _terms[spaceKey];
        address recipient = currentTerms.treasury != address(0)
            ? currentTerms.treasury
            : azimuth.getOwner(ownerId);

        if (
            !_isPointController(ownerId, msg.sender) &&
            (currentTerms.treasury == address(0) || msg.sender != currentTerms.treasury)
        ) {
            revert UnauthorizedClaim();
        }

        amount = claimable[spaceKey][token];
        if (amount == 0) revert NothingToClaim();

        claimable[spaceKey][token] = 0;
        IERC20(token).safeTransfer(recipient, amount);
        emit DuesClaimed(spaceKey, token, recipient, amount);
    }

    function getTerms(bytes32 spaceKey) external view returns (Terms memory) {
        return _terms[spaceKey];
    }

    function _requireHubController() internal view {
        uint32 hubOwnerId = spacePort.getOwnerId();
        if (!_isPointController(hubOwnerId, msg.sender)) revert UnauthorizedHubController();
    }

    function _requireLiveSpaceController(bytes32 spaceKey) internal view returns (uint32 ownerId) {
        ownerId = _requireLiveSpace(spaceKey);
        if (!_isPointController(ownerId, msg.sender)) revert UnauthorizedSpaceController();
    }

    function _requireLiveSpace(bytes32 spaceKey) internal view returns (uint32 ownerId) {
        ownerId = _requireSpaceExists(spaceKey);
        if (spacePort.isDestroyed(spaceKey)) revert SpaceDestroyed();
    }

    function _requireSpaceExists(bytes32 spaceKey) internal view returns (uint32 ownerId) {
        if (!spacePort.exists(spaceKey)) revert SpaceDoesNotExist();
        (ownerId,,,,,,) = spacePort.getSpace(spaceKey);
    }

    function _isPointController(uint32 point, address who) internal view returns (bool) {
        return azimuth.isOwner(point, who) || azimuth.isManagementProxy(point, who);
    }

    function _graceEnds(uint64 paidUntil, uint64 graceSeconds) internal pure returns (uint64) {
        if (paidUntil == 0) return 0;
        unchecked {
            uint64 ends = paidUntil + graceSeconds;
            return ends < paidUntil ? type(uint64).max : ends;
        }
    }
}
