// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20
} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    IEscrowVault
} from "../interfaces/IEscrowVault.sol";

import "../libraries/BondErrors.sol";

/// @title EscrowVault
/// @notice Holds USDT for one bond issuance. All funds are
///         partitioned into four explicit buckets so that
///         balances of different lifecycle stages cannot
///         contaminate each other.
///
///         INVARIANT:
///         usdt.balanceOf(this) >= subscriptionEscrow
///                               + couponReserves
///                               + redemptionReserves
///                               + issuerCollateral
///
///         The contract checks this invariant on every state
///         change.
contract EscrowVault is
    IEscrowVault,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    // =====================================================
    // STORAGE
    // =====================================================

    IERC20 public immutable usdt;

    address public immutable bondContract;

    /// Bucket 1: subscription funds locked from investors
    /// before issuance is finalized. Drains via:
    ///   - refundInvestor   (back to investor)
    ///   - releaseToIssuer  (forward to issuer)
    uint256 public subscriptionEscrow;

    /// Bucket 2: coupon reserves funded by issuer.
    /// Drains via payCouponClaim during push-payouts.
    uint256 public couponReserves;

    /// Bucket 3: redemption reserve funded by issuer.
    /// Drains via payRedemption during push-redemption.
    uint256 public redemptionReserves;

    /// Bucket 4: collateral deposited by the issuer at
    /// confirmIssue. Drains via:
    ///   - releaseIssuerCollateral        (NOT_ISSUED path,
    ///                                     back to issuer)
    ///   - convertCollateralToRedemption  (used as part of
    ///                                     the redemption
    ///                                     reserve)
    uint256 public issuerCollateral;

    // =====================================================
    // EVENTS
    // =====================================================

    event SubscriptionFundsLocked(
        address indexed investor,
        uint256 amount
    );

    event FundsReleasedToIssuer(
        address indexed issuer,
        uint256 amount
    );

    event SubscriptionRefunded(
        address indexed investor,
        uint256 amount
    );

    event CouponReserveDeposited(
        address indexed issuer,
        uint256 amount
    );

    event CouponClaimPaid(
        address indexed investor,
        uint256 amount
    );

    event RedemptionReserveDeposited(
        address indexed issuer,
        uint256 amount
    );

    event RedemptionPaidOut(
        address indexed investor,
        uint256 amount
    );

    event IssuerCollateralLocked(
        address indexed issuer,
        uint256 amount
    );

    event IssuerCollateralReleased(
        address indexed issuer,
        uint256 amount
    );

    event CollateralConvertedToRedemption(uint256 amount);

    // =====================================================
    // MODIFIERS
    // =====================================================

    modifier onlyBondContract() {
        if (msg.sender != bondContract) {
            revert OnlyBondContract();
        }
        _;
    }

    // =====================================================
    // CONSTRUCTOR
    // =====================================================

    constructor(
        address _usdt,
        address _bondContract
    ) {
        if (_usdt == address(0)) {
            revert ZeroAddress();
        }

        if (_bondContract == address(0)) {
            revert ZeroAddress();
        }

        usdt = IERC20(_usdt);
        bondContract = _bondContract;
    }

    // =====================================================
    // SUBSCRIPTION ESCROW BUCKET
    // =====================================================

    function lockSubscriptionFunds(
        address investor,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        subscriptionEscrow += amount;

        usdt.safeTransferFrom(
            investor,
            address(this),
            amount
        );

        _assertInvariant();

        emit SubscriptionFundsLocked(investor, amount);
    }

    function releaseToIssuer(
        address issuer,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > subscriptionEscrow) {
            revert InsufficientReserve();
        }

        subscriptionEscrow -= amount;

        usdt.safeTransfer(issuer, amount);

        _assertInvariant();

        emit FundsReleasedToIssuer(issuer, amount);
    }

    function refundInvestor(
        address investor,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > subscriptionEscrow) {
            revert InsufficientReserve();
        }

        subscriptionEscrow -= amount;

        usdt.safeTransfer(investor, amount);

        _assertInvariant();

        emit SubscriptionRefunded(investor, amount);
    }

    // =====================================================
    // COUPON RESERVES BUCKET
    // =====================================================

    function fundCouponReserve(
        address issuer,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        couponReserves += amount;

        usdt.safeTransferFrom(
            issuer,
            address(this),
            amount
        );

        _assertInvariant();

        emit CouponReserveDeposited(issuer, amount);
    }

    function payCouponClaim(
        address investor,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > couponReserves) {
            revert InsufficientReserve();
        }

        couponReserves -= amount;

        usdt.safeTransfer(investor, amount);

        _assertInvariant();

        emit CouponClaimPaid(investor, amount);
    }

    // =====================================================
    // REDEMPTION RESERVE BUCKET
    // =====================================================

    function fundRedemptionReserve(
        address issuer,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        redemptionReserves += amount;

        usdt.safeTransferFrom(
            issuer,
            address(this),
            amount
        );

        _assertInvariant();

        emit RedemptionReserveDeposited(issuer, amount);
    }

    function payRedemption(
        address investor,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > redemptionReserves) {
            revert InsufficientReserve();
        }

        redemptionReserves -= amount;

        usdt.safeTransfer(investor, amount);

        _assertInvariant();

        emit RedemptionPaidOut(investor, amount);
    }

    // =====================================================
    // ISSUER COLLATERAL BUCKET
    // =====================================================

    function lockIssuerCollateral(
        address issuer,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        issuerCollateral += amount;

        usdt.safeTransferFrom(
            issuer,
            address(this),
            amount
        );

        _assertInvariant();

        emit IssuerCollateralLocked(issuer, amount);
    }

    function releaseIssuerCollateral(
        address issuer,
        uint256 amount
    )
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > issuerCollateral) {
            revert InsufficientReserve();
        }

        issuerCollateral -= amount;

        usdt.safeTransfer(issuer, amount);

        _assertInvariant();

        emit IssuerCollateralReleased(issuer, amount);
    }

    /// @notice Move collateral into the redemption reserve
    ///         in-place. No USDT leaves the vault.
    function convertCollateralToRedemption(uint256 amount)
        external
        onlyBondContract
        nonReentrant
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > issuerCollateral) {
            revert InsufficientReserve();
        }

        issuerCollateral -= amount;
        redemptionReserves += amount;

        _assertInvariant();

        emit CollateralConvertedToRedemption(amount);
    }

    // =====================================================
    // VIEWS
    // =====================================================

    function expectedBalance()
        external
        view
        returns (uint256)
    {
        return
            subscriptionEscrow +
            couponReserves +
            redemptionReserves +
            issuerCollateral;
    }

    function actualBalance()
        external
        view
        returns (uint256)
    {
        return usdt.balanceOf(address(this));
    }

    // =====================================================
    // INTERNAL
    // =====================================================

    /// Defensive check: the on-chain balance must cover the
    /// sum of internal buckets. Strict equality is not used
    /// because a malicious actor could donate USDT directly
    /// to the vault to inflate the actual balance, which is
    /// harmless and only creates unowned dust.
    function _assertInvariant() internal view {
        uint256 expected =
            subscriptionEscrow +
            couponReserves +
            redemptionReserves +
            issuerCollateral;

        if (usdt.balanceOf(address(this)) < expected) {
            revert AccountingMismatch();
        }
    }
}
