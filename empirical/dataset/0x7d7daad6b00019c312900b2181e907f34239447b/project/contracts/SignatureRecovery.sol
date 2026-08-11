// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SignatureRecovery {
    function toEthSignedMessageHash(bytes32 _message) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _message));
    }
    function split(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
    function recover(bytes32 _message, bytes memory _signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = split(_signature);
        return ecrecover(toEthSignedMessageHash(_message), v, r, s);
    }
}
