// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title RoyaltySplitter — auto-forward ETH to two recipients on a fixed BPS split
/// @notice Receives ETH (e.g. from marketplaces forwarding EIP-2981 royalties)
///         and immediately fan-outs the amount to recipients A and B according
///         to a BPS split set at deploy. No claim flow — recipients see ETH
///         arrive in their wallet on every secondary sale.
/// @dev    Both recipients MUST be able to accept arbitrary ETH (EOAs are
///         safest; payable smart wallets are fine; contracts that revert in
///         their `receive()` would brick the splitter).
contract RoyaltySplitter {
    address public immutable recipientA;
    address public immutable recipientB;
    uint16  public immutable bpsA; // 0..10000

    uint16 public constant BPS_DENOMINATOR = 10000;

    event RoyaltyForwarded(uint256 totalIn, uint256 toA, uint256 toB);

    error ZeroAddress();
    error BpsOutOfRange();
    error ForwardFailed();

    constructor(address a, address b, uint16 _bpsA) {
        if (a == address(0) || b == address(0)) revert ZeroAddress();
        if (_bpsA == 0 || _bpsA > BPS_DENOMINATOR) revert BpsOutOfRange();
        recipientA = a;
        recipientB = b;
        bpsA = _bpsA;
    }

    receive() external payable {
        _split(msg.value);
    }

    /// @notice Manual entry point in case a sender doesn't trigger receive()
    ///         (e.g. a marketplace using a low-level call without value-only).
    fallback() external payable {
        _split(msg.value);
    }

    function _split(uint256 amount) internal {
        if (amount == 0) return;
        uint256 shareA = (amount * bpsA) / BPS_DENOMINATOR;
        uint256 shareB = amount - shareA; // exact arithmetic, no dust
        (bool okA,) = recipientA.call{value: shareA}("");
        if (!okA) revert ForwardFailed();
        (bool okB,) = recipientB.call{value: shareB}("");
        if (!okB) revert ForwardFailed();
        emit RoyaltyForwarded(amount, shareA, shareB);
    }
}
