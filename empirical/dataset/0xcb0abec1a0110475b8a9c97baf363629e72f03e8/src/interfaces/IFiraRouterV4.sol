// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Minimal subset of Fira Router V4 used by FiraLiquidator: the USDC -> BT swap
// leg of fixed-rate liquidation. The struct tree below mirrors Fira's
// IPAllActionTypeV3 / IPLimitRouter EXACTLY so calldata encodes identically to
// the live router — do not reorder or retype fields.

enum SwapType {
    NONE,
    KYBERSWAP,
    ODOS,
    ETH_WETH,
    OKX,
    ONE_INCH,
    RESERVE_1,
    RESERVE_2,
    RESERVE_3
}

struct SwapData {
    SwapType swapType;
    address extRouter;
    bytes extCalldata;
    bool needScale;
}

struct TokenInput {
    address tokenIn;
    uint256 netTokenIn;
    address tokenMintFw;
    address firaSwap;
    SwapData swapData;
}

struct ApproxParams {
    uint256 guessMin;
    uint256 guessMax;
    uint256 guessOffchain;
    uint256 maxIteration;
    uint256 eps;
}

enum OrderType {
    FW_FOR_BT,
    BT_FOR_FW,
    FW_FOR_CT,
    CT_FOR_FW
}

struct Order {
    uint256 salt;
    uint256 expiry;
    uint256 nonce;
    OrderType orderType;
    address token;
    address CT;
    address maker;
    address receiver;
    uint256 makingAmount;
    uint256 lnImpliedRate;
    uint256 failSafeRate;
    bytes permit;
}

struct FillOrderParams {
    Order order;
    bytes signature;
    uint256 makingAmount;
}

struct LimitOrderData {
    address limitRouter;
    uint256 epsSkipMarket;
    FillOrderParams[] normalFills;
    FillOrderParams[] flashFills;
    bytes optData;
}

interface IFiraRouterV4 {
    /// @notice Swap an exact amount of `input` token into BT on the Fira AMM,
    /// requiring at least `minBtOut`. Exact-token-in / approximate-BT-out.
    /// @dev AMM-based: reverts `MarketExpired()` after maturity. Use
    /// `mintBcFromToken` for the post-maturity BT-acquisition path.
    /// @return netBtOut BT delivered to `receiver`.
    function swapExactTokenForBt(
        address receiver,
        address market,
        uint256 minBtOut,
        ApproxParams calldata guessBtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netBtOut, uint256 netFwFee, uint256 netFwInterm);

    /// @notice Mint BC (equal BT + CT) from `input` token by depositing into FW
    /// then tokenizing, requiring at least `minBcOut`. Works post-maturity (no
    /// AMM), unlike `swapExactTokenForBt`. Mints to `receiver`; the CT half is a
    /// by-product the caller keeps.
    /// @param CT The CouponToken whose BT/CT pair is minted.
    /// @return netBcOut Amount of BT (== CT) minted to `receiver`.
    function mintBcFromToken(address receiver, address CT, uint256 minBcOut, TokenInput calldata input)
        external
        payable
        returns (uint256 netBcOut, uint256 netFwInterm);
}

/// @notice Minimal Fira AMM view to resolve the FW/BT/CT triplet for a market.
interface IFiraMarketTokens {
    function readTokens() external view returns (address FW, address BT, address CT);
}
