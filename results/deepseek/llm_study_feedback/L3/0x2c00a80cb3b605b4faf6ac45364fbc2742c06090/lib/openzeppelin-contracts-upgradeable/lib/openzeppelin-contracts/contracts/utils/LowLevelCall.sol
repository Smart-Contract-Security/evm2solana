// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LowLevelCall {
    function callNoReturn(address target, bytes memory data) internal returns (bool success) {
        return callNoReturn(target, 0, data);
    }

    function callNoReturn(address target, uint256 value, bytes memory data) internal returns (bool success) {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: true});
        (success, ) = target.call{value: value, accounts: metas}(data);
    }

    function callReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        return callReturn64Bytes(target, 0, data);
    }

    function callReturn64Bytes(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory ret;
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: true});
        (success, ret) = target.call{value: value, accounts: metas}(data);
        if (success && ret.length >= 64) {
            result1 = abi.decode(ret, (bytes32));
            result2 = abi.decode(ret[32:], (bytes32));
        }
    }

    function staticcallNoReturn(address target, bytes memory data) internal view returns (bool success) {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: false});
        (success, ) = target.call{accounts: metas}(data);
    }

    function staticcallReturn64Bytes(
        address target,
        bytes memory data
    ) internal view returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory ret;
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: false});
        (success, ret) = target.call{accounts: metas}(data);
        if (success && ret.length >= 64) {
            result1 = abi.decode(ret, (bytes32));
            result2 = abi.decode(ret[32:], (bytes32));
        }
    }

    function delegatecallNoReturn(address target, bytes memory data) internal returns (bool success) {
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: true});
        (success, ) = target.call{accounts: metas}(data);
    }

    function delegatecallReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory ret;
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: target, is_signer: false, is_writable: true});
        (success, ret) = target.call{accounts: metas}(data);
        if (success && ret.length >= 64) {
            result1 = abi.decode(ret, (bytes32));
            result2 = abi.decode(ret[32:], (bytes32));
        }
    }

    function returnDataSize() internal pure returns (uint256 size) {
        size = 0;
    }

    function returnData() internal pure returns (bytes memory result) {
        result = new bytes(0);
    }

    function bubbleRevert() internal pure {
        revert("bubbleRevert");
    }

    function bubbleRevert(bytes memory returndata) internal pure {
        revert(string(returndata));
    }
}