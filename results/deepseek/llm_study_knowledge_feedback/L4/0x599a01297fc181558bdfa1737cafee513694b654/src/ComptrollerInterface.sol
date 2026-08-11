// SPDX-License-Identifier: BSD-3-Clause

abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(
        address[] calldata mTokens
    ) external virtual returns (uint64[] memory);
    function exitMarket(address mToken) external virtual returns (uint64);

    /*** Policy Hooks ***/

    function mintAllowed(
        address mToken,
        address minter,
        uint64 mintAmount
    ) external virtual returns (uint64);

    function redeemAllowed(
        address mToken,
        address redeemer,
        uint64 redeemTokens
    ) external virtual returns (uint64);

    // Do not remove, still used by MToken
    function redeemVerify(
        address mToken,
        address redeemer,
        uint64 redeemAmount,
        uint64 redeemTokens
    ) external pure virtual;

    function borrowAllowed(
        address mToken,
        address borrower,
        uint64 borrowAmount
    ) external virtual returns (uint64);

    function repayBorrowAllowed(
        address mToken,
        address payer,
        address borrower,
        uint64 repayAmount
    ) external virtual returns (uint64);

    function liquidateBorrowAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint64 repayAmount
    ) external view virtual returns (uint64);

    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint64 seizeTokens
    ) external virtual returns (uint64);

    function transferAllowed(
        address mToken,
        address src,
        address dst,
        uint64 transferTokens
    ) external virtual returns (uint64);

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint64 repayAmount
    ) external view virtual returns (uint64, uint64);
}

// The hooks that were patched out of the comptroller to make room for the supply caps, if we need them
abstract contract ComptrollerInterfaceWithAllVerificationHooks is
    ComptrollerInterface
{
    function mintVerify(
        address mToken,
        address minter,
        uint64 mintAmount,
        uint64 mintTokens
    ) external virtual;

    // Included in ComptrollerInterface already
    // function redeemVerify(address mToken, address redeemer, uint redeemAmount, uint redeemTokens) virtual external;

    function borrowVerify(
        address mToken,
        address borrower,
        uint64 borrowAmount
    ) external virtual;

    function repayBorrowVerify(
        address mToken,
        address payer,
        address borrower,
        uint64 repayAmount,
        uint64 borrowerIndex
    ) external virtual;

    function liquidateBorrowVerify(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint64 repayAmount,
        uint64 seizeTokens
    ) external virtual;

    function seizeVerify(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint64 seizeTokens
    ) external virtual;

    function transferVerify(
        address mToken,
        address src,
        address dst,
        uint64 transferTokens
    ) external virtual;
}