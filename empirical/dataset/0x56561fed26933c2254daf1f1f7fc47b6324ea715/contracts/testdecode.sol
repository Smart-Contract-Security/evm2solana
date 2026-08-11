// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Decoder {
    struct SubNodeOperator {
        uint64 nodeOperatorId;
        uint16 share;
    }

    struct ExternalOperator {
        bytes data;
    }

    struct GroupInfo {
        SubNodeOperator[] subNodeOperators;
        ExternalOperator[] externalOperators;
    }

    function decodeEVMScriptCallData(bytes memory returnData)
        public
        pure
        returns (uint256 groupId, GroupInfo memory groupInfo)
    {
        (groupId, groupInfo) = abi.decode(returnData, (uint256, GroupInfo));
    }
}