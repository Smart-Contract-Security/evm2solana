// Solana port using Solang compiler
pragma solidity ^0.8.24;

contract VerifySignature {
    function getMessageHash(
        address _to,
        uint256 _amount,
        string memory _message,
        uint256 _id
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_to, _amount, _message, _id));
    }

    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
        );
    }

    function verify(
        uint256 _id,
        address _to,
        uint256 _amount,
        string memory _message,
        bytes memory signature
    ) public view returns (address) {
        bytes32 messageHash = getMessageHash(_to, _amount, _message, _id);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return recoverSigner(ethSignedMessageHash, signature);
    }

    function recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) public view returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        // Solang does not support inline assembly, so we extract manually
        r = bytes32(sig[0:32]);
        s = bytes32(sig[32:64]);
        v = uint8(sig[64]);
    }
}