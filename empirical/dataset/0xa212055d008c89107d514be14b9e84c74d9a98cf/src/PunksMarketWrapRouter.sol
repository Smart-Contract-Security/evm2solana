// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IPunksMarket, ICryptoPunksV1, IPunksV1Wrapper} from "./Interfaces.sol";

/// @title  PunksMarketWrapRouter
/// @notice Buys a V1 CryptoPunk listed on PunksMarket (2026) and returns it already wrapped (WPV1)
///         in a single transaction. Native V1 punks are not ERC-721, and the wrapper takes
///         custody through a directed offer at price 0 rather than a transfer, so wrapping
///         takes three steps: buy, offer to the wrapper, then wrap. This contract runs all
///         three atomically and sends the wrapped token to the caller.
/// @dev    Stateless, ownerless and permissionless. Holds no funds or tokens between calls
///         and grants no approvals. The wrapped punk always goes to msg.sender, so any
///         account (wallet or contract) can call it.
contract PunksMarketWrapRouter {
    // PunksMarket: settles directed listings of native V1 punks.
    IPunksMarket public constant MARKET = IPunksMarket(0x64e507FEBF26521b73FbdfA533106B2042533218);
    // The original June 9th 2017 CryptoPunks contract (native punk ownership).
    ICryptoPunksV1 public constant PUNKS_V1 = ICryptoPunksV1(0x6Ba6f2207e343923BA692e5Cae646Fb0F566DB8D);
    // Canonical WPV1 ERC-721 wrapper for V1 punks (FrankNFT.eth).
    IPunksV1Wrapper public constant WRAPPER = IPunksV1Wrapper(0x282BDD42f4eb70e7A9D9F40c8fEA0825B7f68C5D);

    bool transient private _locked;

    error IncorrectPayment();
    error RefundFailed();
    error Reentrancy();

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    /// @param punkId     Punk to buy; must be a live listing directed to PunksMarket.
    /// @param listingWei The listing's exact price; any excess msg.value is refunded to the caller.
    function buyAndWrap(uint16 punkId, uint96 listingWei) external payable nonReentrant {
        if (msg.value < listingWei) revert IncorrectPayment();

        MARKET.buyPunk{value: listingWei}(punkId, listingWei, address(this));

        // The wrapper takes custody via a directed offer at price 0, not a transfer (no receive hook).
        PUNKS_V1.offerPunkForSaleToAddress(punkId, 0, address(WRAPPER));
        WRAPPER.wrap(punkId);

        WRAPPER.safeTransferFrom(address(this), msg.sender, punkId);

        // Refund from msg.value rather than the contract balance, so nested calls cannot drain one another.
        uint256 refund = msg.value - listingWei;
        if (refund != 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundFailed();
        }
    }
}
