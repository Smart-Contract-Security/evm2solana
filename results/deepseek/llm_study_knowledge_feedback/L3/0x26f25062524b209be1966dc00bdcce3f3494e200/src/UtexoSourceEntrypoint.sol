// SPDX-License-Identifier: MIT

import { IOFT, SendParam } from '@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol';
import { MessagingFee, MessagingReceipt } from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';

contract UtexoSourceEntrypoint {
    string constant InvalidTokenAddress = "InvalidTokenAddress";
    string constant InvalidOftAddress = "InvalidOftAddress";
    string constant InvalidDstEid = "InvalidDstEid";
    string constant InvalidLZAdapter = "InvalidLZAdapter";
    string constant ZeroAmount = "ZeroAmount";
    string constant InsufficientNativeFee = "InsufficientNativeFee";

    event Deposit(
        bytes32 guid,
        address sender,
        uint256 amountLD,
        uint256 sourceChainId,
        uint256 destinationChainId,
        string destinationAddress,
        uint256 operationId,
        bytes settlementData
    );

    struct DepositParams {
        uint256 amountLD;
        uint256 minAmountLD;
        bytes extraOptions;
        bytes payload;
    }

    address public immutable token;
    address public immutable oft;
    uint32 public immutable dstEid;
    bytes32 public immutable lzAdapter;

    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(
        address token_,
        address oft_,
        uint32 dstEid_,
        bytes32 lzAdapter_
    ) {
        require(token_ != address(0), InvalidTokenAddress);
        require(oft_ != address(0), InvalidOftAddress);
        require(dstEid_ != 0, InvalidDstEid);
        require(lzAdapter_ != bytes32(0), InvalidLZAdapter);

        token = token_;
        oft = oft_;
        dstEid = dstEid_;
        lzAdapter = lzAdapter_;
    }

    function deposit(DepositParams calldata depositParams)
        external
        nonReentrant
        returns (bytes32 guid)
    {
        require(depositParams.amountLD != 0, ZeroAmount);

        // Transfer tokens from user to this contract using SPL Token program
        uint64 amount64 = uint64(depositParams.amountLD);
        bytes memory transferData = abi.encodePacked(uint8(3), amount64);
        (bool transferSuccess, ) = token.call(transferData);
        require(transferSuccess, "Token transfer failed");

        // Approve OFT to spend tokens
        bytes memory approveData = abi.encodePacked(uint8(4), amount64);
        (bool approveSuccess, ) = token.call(approveData);
        require(approveSuccess, "Token approve failed");

        // Decode payload
        (uint256 destinationChainId, string memory destinationAddress, uint256 operationId, bytes memory settlementData) =
            abi.decode(depositParams.payload, (uint256, string, uint256, bytes));

        // Build compose message
        bytes memory composeMsg = abi.encode(
            block.chainid,
            destinationChainId,
            destinationAddress,
            operationId,
            settlementData
        );

        // Prepare SendParam for OFT
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: lzAdapter,
            amountLD: depositParams.amountLD,
            minAmountLD: depositParams.minAmountLD,
            extraOptions: depositParams.extraOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote fee
        MessagingFee memory fee = IOFT(oft).quoteSend(sendParam, false);

        // Check native fee
        require(address(this).balance >= fee.nativeFee, InsufficientNativeFee);

        // Send via OFT
        MessagingReceipt memory receipt = IOFT(oft).send{value: fee.nativeFee}(sendParam, fee, msg.sender);
        guid = receipt.guid;

        // Refund excess native fee
        uint256 refund = address(this).balance;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
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
}