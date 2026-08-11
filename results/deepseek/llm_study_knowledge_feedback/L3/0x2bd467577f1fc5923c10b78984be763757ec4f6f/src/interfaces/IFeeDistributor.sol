// SPDX-License-Identifier: MIT

import 'solana';

interface IFeeDistributor {
    // Error definitions are not yet working for Solana, so we omit them.
    // Instead, we rely on require statements or revert without messages.

    event TaxReceived(
        uint64 amount,
        uint64 lpShare,
        uint64 boardwalkShare,
        uint64 issuerShare,
        uint64 referrerShare,
        uint64 integratorShare
    );
    event IssuerClaimed(
        uint64 recipientIdx, address recipient, uint64 tokenAmount, uint64 raiseTokenAmount
    );
    event ReferrerClaimed(address referrer, uint64 amount);
    event IssuerAddressChanged(uint64 recipientIdx, address oldAddress, address newAddress);
    event ReferrerAddressChanged(address oldAddress, address newAddress);
    event FeeCollectorChanged(address oldCollector, address newCollector);
    event FeeForwardFailed(string target, uint64 amount);

    struct InitParams {
        address token;
        address lpStaking;
        address feeCollector;
        address integratorCollector;
        address router;
        address raiseToken;
        address[] issuerRecipients;
        uint64[] issuerSplits;
        address referrer;
        uint64 issuerBps;
        uint64 boardwalkBps;
        uint64 lpIncentiveBps;
        uint64 referrerBps;
        uint64 integratorBps;
    }

    function initialize(
        InitParams calldata p
    ) external;
    function onTaxReceived(
        uint64 amount
    ) external;
    function claimAsRaiseToken(
        uint64 recipientIdx,
        uint64 minRaiseTokenOut,
        uint64 deadline
    ) external;
    function claimReferrerFees() external;
    function claimableAmount(
        uint64 recipientIdx
    ) external view returns (uint64);
    function referrerAccrued() external view returns (uint64);
    function issuerRecipients(
        uint64 idx
    ) external view returns (address);
    function token() external view returns (address);
    function integratorCollector() external view returns (address);
    function retryPendingFees() external;
    function pendingLpFees() external view returns (uint64);
    function pendingBoardwalkFees() external view returns (uint64);
    function pendingIntegratorFees() external view returns (uint64);
    function feeCollector() external view returns (address);
    function setFeeCollector(
        address newFeeCollector
    ) external;
}