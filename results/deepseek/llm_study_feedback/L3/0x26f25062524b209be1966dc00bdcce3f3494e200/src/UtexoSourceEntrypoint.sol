// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { IOFT, SendParam } from '@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol';
import { MessagingFee, MessagingReceipt } from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';

struct DepositParams {
    uint256 amountLD;
    uint256 minAmountLD;
    bytes extraOptions;
    bytes payload;
}

interface IUtexoSourceEntrypoint {
    function token() external view returns (address);
    function oft() external view returns (address);
    function dstEid() external view returns (uint32);
    function lzAdapter() external view returns (bytes32);
    function deposit(DepositParams calldata depositParams) external payable returns (bytes32 guid);
    function quote(DepositParams calldata depositParams) external view returns (uint256 nativeFee);
    event Deposit(bytes32 indexed guid, address indexed sender, uint256 amountLD, uint256 srcChainId, uint256 dstChainId, string dstAddress, uint256 operationId, bytes settlementData);
}

contract UtexoSourceEntrypoint is IUtexoSourceEntrypoint {
    using SafeERC20 for IERC20;

    address public immutable token;
    address public immutable oft;
    uint32  public immutable dstEid;
    bytes32 public immutable lzAdapter;

    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(
        address token_,
        address oft_,
        uint32  dstEid_,
        bytes32 lzAdapter_
    ) {
        require(token_ != address(0), "InvalidTokenAddress");
        require(oft_ != address(0), "InvalidOftAddress");
        require(dstEid_ != 0, "InvalidDstEid");
        require(lzAdapter_ != bytes32(0), "InvalidLZAdapter");

        token     = token_;
        oft       = oft_;
        dstEid    = dstEid_;
        lzAdapter = lzAdapter_;
    }

    function deposit(DepositParams calldata depositParams)
        external
        payable
        nonReentrant
        returns (bytes32 guid)
    {
        require(depositParams.amountLD != 0, "ZeroAmount");

        IERC20(token).safeTransferFrom(msg.sender, address(this), depositParams.amountLD);
        IERC20(token).safeIncreaseAllowance(oft, depositParams.amountLD);

        (
            uint256 destinationChainId,
            string memory destinationAddress,
            uint256 operationId,
            bytes memory settlementData
        ) = abi.decode(depositParams.payload, (uint256, string, uint256, bytes));

        uint256 chainId = block.chainid;

        bytes memory composeMsg = abi.encode(
            chainId,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );

        SendParam memory sp = SendParam({
            dstEid:       dstEid,
            to:           lzAdapter,
            amountLD:     depositParams.amountLD,
            minAmountLD:  depositParams.minAmountLD,
            extraOptions: depositParams.extraOptions,
            composeMsg:   composeMsg,
            oftCmd:       ''
        });

        MessagingFee memory fee = IOFT(oft).quoteSend(sp, false);
        require(msg.value >= fee.nativeFee, "InsufficientNativeFee");

        (MessagingReceipt memory receipt, ) =
            IOFT(oft).send{ value: fee.nativeFee }(sp, fee, msg.sender);
        guid = receipt.guid;

        uint256 excess = msg.value - fee.nativeFee;
        if (excess != 0) {
            (bool ok, ) = msg.sender.call{ value: excess }('');
            require(ok, "NativeRefundFailed");
        }

        emit Deposit(
            guid,
            msg.sender,
            depositParams.amountLD,
            chainId,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );
    }

    function quote(DepositParams calldata depositParams)
        external
        view
        returns (uint256 nativeFee)
    {
        (
            uint256 destinationChainId,
            string memory destinationAddress,
            uint256 operationId,
            bytes memory settlementData
        ) = abi.decode(depositParams.payload, (uint256, string, uint256, bytes));

        uint256 chainId = block.chainid;

        bytes memory composeMsg = abi.encode(
            chainId,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );
        SendParam memory sp = SendParam({
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