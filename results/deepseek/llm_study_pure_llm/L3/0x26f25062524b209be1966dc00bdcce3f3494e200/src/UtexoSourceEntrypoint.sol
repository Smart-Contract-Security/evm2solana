// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface IOFT {
    struct SendParam {
        uint32 dstEid;
        bytes32 to;
        uint256 amountLD;
        uint256 minAmountLD;
        bytes extraOptions;
        bytes composeMsg;
        bytes oftCmd;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken) external view returns (MessagingFee memory);
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress) external payable returns (MessagingReceipt memory, bytes memory);
}

interface IUtexoSourceEntrypoint {
    struct DepositParams {
        uint256 amountLD;
        uint256 minAmountLD;
        bytes extraOptions;
        bytes payload;
    }

    event Deposit(
        bytes32 indexed guid,
        address indexed sender,
        uint256 amountLD,
        uint256 sourceChainId,
        uint256 destinationChainId,
        string destinationAddress,
        uint256 operationId,
        bytes settlementData
    );

    error InvalidTokenAddress();
    error InvalidOftAddress();
    error InvalidDstEid();
    error InvalidLZAdapter();
    error ZeroAmount();
    error InsufficientNativeFee(uint256 provided, uint256 required);
    error NativeRefundFailed();

    function token() external view returns (address);
    function oft() external view returns (address);
    function dstEid() external view returns (uint32);
    function lzAdapter() external view returns (bytes32);

    function deposit(DepositParams calldata depositParams) external payable returns (bytes32 guid);
    function quote(DepositParams calldata depositParams) external view returns (uint256 nativeFee);
}

/// @title UtexoSourceEntrypoint
/// @notice Utexo's user-facing deposit contract on source chains (Ethereum, OP, Base, …).
/// @dev
///     ┌────────────┐ transferFrom  ┌────────────────────┐   OFT.send    ┌──────────────┐
///     │  user EOA  │──────────────▶│ UtexoSource        │──────────────▶│ USDT0 OFT    │
///     └────────────┘               │ Entrypoint (this)  │               └──────┬───────┘
///                                  └────────────────────┘                      │
///                                                                              │ LayerZero
///                                                                              ▼
///                                                               ┌──────────────────────┐
///                                                               │ UtexoLZAdapter       │
///                                                               │ (destination chain)  │
///                                                               └──────────────────────┘
///
///     Properties:
///       • Stateless — only immutables.
///       • Non-upgradeable. Replacement = redeploy; no owner, no pause, no admin.
///       • `dstEid` and `lzAdapter` are fixed at construction and cannot be
///         re-pointed at a different destination by the caller or anyone else.
///       • `composeMsg` is built by the entrypoint as
///         `abi.encode(block.chainid, destinationChainId, destinationAddress, operationId, settlementData)`,
///         where the destination fields and `settlementData` are extracted from
///         the caller-supplied `payload` blob via `abi.decode`. All chain
///         identifiers are `uint256` (real `block.chainid` for EVM endpoints,
///         backend-assigned ids above the EVM range). `settlementData` is an opaque blob whose layout
///         is dictated by the destination route's `SettlementModule` on
///         Arbitrum — the entrypoint plumbs it through unchanged. For routes
///         registered with `NullSettlementModule` (the default for LZ-adapter
///         flows) it is empty (`""`). A malformed `payload` reverts here on the
///         source chain so no LZ fee is ever paid for an un-decodable compose,
///         and the `sourceChainId` part is non-spoofable.
///       • LayerZero fee is re-quoted on-chain; surplus `msg.value` is refunded to
///         `msg.sender`.
contract UtexoSourceEntrypoint is IUtexoSourceEntrypoint {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Immutables
    // =========================================================================

    /// @inheritdoc IUtexoSourceEntrypoint
    address public immutable override token;

    /// @inheritdoc IUtexoSourceEntrypoint
    address public immutable override oft;

    /// @inheritdoc IUtexoSourceEntrypoint
    uint32  public immutable override dstEid;

    /// @inheritdoc IUtexoSourceEntrypoint
    bytes32 public immutable override lzAdapter;

    // =========================================================================
    // Reentrancy guard state
    // =========================================================================

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @param token_      ERC-20 that will be pulled from users and forwarded into
    ///                    the OFT. On Ethereum this is canonical USDT; on chains
    ///                    where USDT0 is native this is the USDT0 token itself.
    /// @param oft_        USDT0 OFT on this chain.
    /// @param dstEid_     LayerZero endpoint id of the destination chain (Arbitrum).
    /// @param lzAdapter_  `UtexoLZAdapter` address on the destination chain, encoded
    ///                    as bytes32 (address left-padded, per LayerZero V2 convention).
    constructor(
        address token_,
        address oft_,
        uint32  dstEid_,
        bytes32 lzAdapter_
    ) {
        if (token_ == address(0))      revert InvalidTokenAddress();
        if (oft_ == address(0))        revert InvalidOftAddress();
        if (dstEid_ == 0)              revert InvalidDstEid();
        if (lzAdapter_ == bytes32(0))  revert InvalidLZAdapter();

        token     = token_;
        oft       = oft_;
        dstEid    = dstEid_;
        lzAdapter = lzAdapter_;

        _status = _NOT_ENTERED;
    }

    // =========================================================================
    // User entry point
    // =========================================================================

    /// @inheritdoc IUtexoSourceEntrypoint
    function deposit(DepositParams calldata depositParams)
        external
        payable
        override
        nonReentrant
        returns (bytes32 guid)
    {
        if (depositParams.amountLD == 0) revert ZeroAmount();

        // 1. Pull the user's tokens into this contract, then allow the OFT to pull
        //    exactly `amountLD` on `send()`. The OFT consumes the entire allowance
        //    via `transferFrom`;
        IERC20(token).safeTransferFrom(msg.sender, address(this), depositParams.amountLD);
        IERC20(token).safeIncreaseAllowance(oft, depositParams.amountLD);

        // 2. Decode the caller's payload to validate format and extract the
        //    destination fields, then re-encode the actual `composeMsg` with
        //    `block.chainid` prepended. A malformed `payload` reverts here —
        //    on the source chain, before any LZ fee is paid — so honest deposits
        //    can never feed malformed bytes into `UtexoLZAdapter.lzCompose`.
        (
            uint256 destinationChainId,
            string memory destinationAddress,
            uint256 operationId,
            bytes memory settlementData
        ) = abi.decode(depositParams.payload, (uint256, string, uint256, bytes));

        bytes memory composeMsg = abi.encode(
            block.chainid,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );

        // 3. Build the LayerZero send parameters. `dstEid` and `to` are immutable
        //    on this contract — the caller cannot redirect the funds.
        IOFT.SendParam memory sp = IOFT.SendParam({
            dstEid:       dstEid,
            to:           lzAdapter,
            amountLD:     depositParams.amountLD,
            minAmountLD:  depositParams.minAmountLD,
            extraOptions: depositParams.extraOptions,
            composeMsg:   composeMsg,
            oftCmd:       ''
        });

        // 4. Re-quote the LayerZero fee on-chain. This defends against the window
        //    between `quoteSend` off-chain and transaction inclusion, during which
        //    LayerZero pricing may change.
        IOFT.MessagingFee memory fee = IOFT(oft).quoteSend(sp, false);
        if (msg.value < fee.nativeFee) {
            revert InsufficientNativeFee({ provided: msg.value, required: fee.nativeFee });
        }

        // 5. Forward exactly `fee.nativeFee` to the OFT; refund surplus ourselves.
        //    Using `msg.sender` as `refundAddress` is defensive only: with this call
        //    shape the OFT has no surplus to refund.
        (IOFT.MessagingReceipt memory receipt, ) =
            IOFT(oft).send{ value: fee.nativeFee }(sp, fee, msg.sender);
        guid = receipt.guid;

        // 6. Refund the user's native surplus (msg.value - nativeFee).
        uint256 excess = msg.value - fee.nativeFee;
        if (excess != 0) {
            (bool ok, ) = msg.sender.call{ value: excess }('');
            if (!ok) revert NativeRefundFailed();
        }

        emit Deposit(
            guid,
            msg.sender,
            depositParams.amountLD,
            block.chainid,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );
    }

    /// @inheritdoc IUtexoSourceEntrypoint
    function quote(DepositParams calldata depositParams)
        external
        view
        override
        returns (uint256 nativeFee)
    {
        // Mirror `deposit`'s payload handling so the quote covers the exact
        // composeMsg the actual send would carry.
        (
            uint256 destinationChainId,
            string memory destinationAddress,
            uint256 operationId,
            bytes memory settlementData
        ) = abi.decode(depositParams.payload, (uint256, string, uint256, bytes));

        bytes memory composeMsg = abi.encode(
            block.chainid,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );
        IOFT.SendParam memory sp = IOFT.SendParam({
            dstEid:       dstEid,
            to:           lzAdapter,
            amountLD:     depositParams.amountLD,
            minAmountLD:  depositParams.minAmountLD,
            extraOptions: depositParams.extraOptions,
            composeMsg:   composeMsg,
            oftCmd:       ''
        });
        return IOFT(oft).quoteSend(sp, false).nativeFee;
    }
}