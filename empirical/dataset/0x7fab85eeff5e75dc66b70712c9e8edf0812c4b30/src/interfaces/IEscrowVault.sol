// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEscrowVault {
    // =====================================================
    // SUBSCRIPTION ESCROW BUCKET
    // =====================================================

    function lockSubscriptionFunds(
        address investor,
        uint256 amount
    ) external;

    function releaseToIssuer(
        address issuer,
        uint256 amount
    ) external;

    function refundInvestor(
        address investor,
        uint256 amount
    ) external;

    // =====================================================
    // COUPON RESERVES BUCKET
    // =====================================================

    function fundCouponReserve(
        address issuer,
        uint256 amount
    ) external;

    function payCouponClaim(
        address investor,
        uint256 amount
    ) external;

    // =====================================================
    // REDEMPTION RESERVE BUCKET
    // =====================================================

    function fundRedemptionReserve(
        address issuer,
        uint256 amount
    ) external;

    function payRedemption(
        address investor,
        uint256 amount
    ) external;

    // =====================================================
    // ISSUER COLLATERAL BUCKET
    // =====================================================

    function lockIssuerCollateral(
        address issuer,
        uint256 amount
    ) external;

    function releaseIssuerCollateral(
        address issuer,
        uint256 amount
    ) external;

    /// Move USDT from issuerCollateral into redemptionReserves
    /// without touching the on-chain USDT balance.
    function convertCollateralToRedemption(uint256 amount)
        external;

    // =====================================================
    // ACCOUNTING VIEWS
    // =====================================================

    function subscriptionEscrow()
        external
        view
        returns (uint256);

    function couponReserves()
        external
        view
        returns (uint256);

    function redemptionReserves()
        external
        view
        returns (uint256);

    function issuerCollateral()
        external
        view
        returns (uint256);

    function expectedBalance()
        external
        view
        returns (uint256);

    function actualBalance()
        external
        view
        returns (uint256);
}
