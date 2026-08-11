// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20}    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal DssPsm interface (used by Sky Protocol's LitePSM
///         and the legacy MakerDAO PSMs interchangeably).
///         buyGem: user supplies DAI, receives `gemAmt` of GEM.
interface IDssPsm {
    function buyGem(address usr, uint256 gemAmt) external;
    function sellGem(address usr, uint256 gemAmt) external;
    function tout() external view returns (uint256);
    function tin()  external view returns (uint256);
    function live() external view returns (uint256);
}

/// @title PsmAdapter
/// @notice Wraps Sky Protocol's LitePSM `buyGem` (DAI → GEM) into a
///         caller-friendly form that takes the DAI amount as input.
///
///         The relay's MultiHopRouter uses `forceApprove + call` to
///         drive hops (HOP_RAW). The native LitePSM `buyGem(usr, gemAmt)`
///         takes a GEM-denominated parameter, so the relay's
///         "patch input-token amount" mechanism can't drive it directly
///         for the DAI → USDC direction.
///
///         This adapter exposes `daiToUsdc(daiAmountIn, recipient)`
///         which:
///           1. Pulls `daiAmountIn` DAI from msg.sender
///           2. Computes the achievable USDC output at peg
///              (accounting for any positive `tout` on the PSM)
///           3. Calls `psm.buyGem(adapter, gemAmt)` — PSM pulls
///              the required DAI from us, sends GEM to us
///           4. Forwards GEM to `recipient`
///           5. Refunds any unused DAI dust back to msg.sender
///
///         Two safety invariants:
///           - `daiUsed <= daiAmountIn` (PSM never pulls more than we approved)
///           - `gemOut == gemAmt` (PSM contract guarantees exact transfer)
///
///         Immutable. No owner. No setter. No upgrade path.
///         To support a new PSM (e.g. USDS-USDC LitePSM), deploy a
///         second PsmAdapter with the new `psm` address.
///
/// @author VoidPool Team
contract PsmAdapter {
    using SafeERC20 for IERC20;

    /// @notice The PSM this adapter targets (e.g. LitePSM-USDC-A)
    IDssPsm public immutable psm;
    /// @notice The DAI-side token (18 decimals)
    IERC20  public immutable dai;
    /// @notice The GEM-side token (e.g. USDC, 6 decimals)
    IERC20  public immutable gem;

    /// @notice Decimal-difference factor: gem amount × scale = dai equivalent
    ///         For USDC (6) ↔ DAI (18): scale = 10^12
    uint256 public immutable scale;

    error AmountTooSmall();
    error NoOutput();

    event AdapterSwap(
        address indexed caller,
        address indexed recipient,
        uint256 daiIn,
        uint256 gemOut,
        uint256 daiRefunded
    );

    /// @param _psm  PSM contract address (e.g. LitePSM-USDC-A)
    /// @param _dai  DAI token address
    /// @param _gem  GEM token address (e.g. USDC)
    /// @param _gemDecimals  Decimals of GEM (e.g. 6 for USDC). Used to
    ///                      compute scale = 10^(18 - gemDecimals).
    constructor(address _psm, address _dai, address _gem, uint8 _gemDecimals) {
        require(_psm != address(0) && _dai != address(0) && _gem != address(0), "zero addr");
        require(_gemDecimals <= 18, "gem decimals too large");
        psm = IDssPsm(_psm);
        dai = IERC20(_dai);
        gem = IERC20(_gem);
        scale = 10 ** (18 - _gemDecimals);

        // Approve infinite DAI to the PSM once at construction. The PSM
        // pulls DAI from us when buyGem is called. forceApprove handles
        // tokens like USDT that revert on non-zero-to-non-zero approvals
        // (DAI doesn't, but uniform style).
        IERC20(_dai).forceApprove(_psm, type(uint256).max);
    }

    /// @notice Swap DAI for GEM via the PSM. Caller must approve DAI
    ///         to this adapter before calling.
    ///
    /// @param daiAmountIn  Amount of DAI to swap (caller approves this)
    /// @param recipient    Address to receive the GEM output. If zero,
    ///                     uses msg.sender.
    /// @return gemOut      Amount of GEM transferred to recipient
    function daiToUsdc(uint256 daiAmountIn, address recipient)
        external
        returns (uint256 gemOut)
    {
        if (recipient == address(0)) recipient = msg.sender;

        // Pull DAI from caller
        dai.safeTransferFrom(msg.sender, address(this), daiAmountIn);

        // Compute the GEM output that DAI can buy, accounting for PSM tout.
        //
        // Maker's DssPsm buyGem semantics:
        //   buyGem(usr, gemAmt) transfers `gemAmt * scale * (WAD + tout) / WAD`
        //   DAI from caller (this adapter), sends gemAmt GEM to usr.
        //
        // Inversion: max gemAmt buyable with daiAmountIn is
        //   gemAmt = daiAmountIn * WAD / (scale * (WAD + tout))
        //
        // tout is in WAD (10^18). For tout=0 the formula reduces to
        //   gemAmt = daiAmountIn / scale
        uint256 tout = psm.tout();
        uint256 WAD  = 1e18;
        uint256 gemAmt;
        if (tout == 0) {
            gemAmt = daiAmountIn / scale;
        } else {
            gemAmt = (daiAmountIn * WAD) / (scale * (WAD + tout));
        }
        if (gemAmt == 0) revert AmountTooSmall();

        // Snapshot GEM balance before PSM call
        uint256 gemBefore = gem.balanceOf(address(this));

        // Execute PSM swap. PSM pulls DAI from us (we pre-approved in ctor)
        // and sends exactly gemAmt GEM to us.
        psm.buyGem(address(this), gemAmt);

        gemOut = gem.balanceOf(address(this)) - gemBefore;
        if (gemOut == 0) revert NoOutput();

        // Forward GEM to recipient
        gem.safeTransfer(recipient, gemOut);

        // Refund any unused DAI dust (caller approved daiAmountIn; PSM may
        // have pulled less due to gemAmt rounding-down or zero-fee math).
        uint256 daiLeft = dai.balanceOf(address(this));
        uint256 refunded;
        if (daiLeft > 0) {
            dai.safeTransfer(msg.sender, daiLeft);
            refunded = daiLeft;
        }

        emit AdapterSwap(msg.sender, recipient, daiAmountIn, gemOut, refunded);
    }

    /// @notice Compute the GEM output for a given DAI input, without
    ///         executing. Useful for off-chain quoting parity.
    function previewDaiToUsdc(uint256 daiAmountIn) external view returns (uint256 gemAmt) {
        uint256 tout = psm.tout();
        uint256 WAD  = 1e18;
        if (tout == 0) {
            gemAmt = daiAmountIn / scale;
        } else {
            gemAmt = (daiAmountIn * WAD) / (scale * (WAD + tout));
        }
    }

    /// @notice Health gate — returns true if the underlying PSM is live.
    ///         The relay polls this to skip the route if PSM is paused.
    function isLive() external view returns (bool) {
        return psm.live() == 1;
    }
}
