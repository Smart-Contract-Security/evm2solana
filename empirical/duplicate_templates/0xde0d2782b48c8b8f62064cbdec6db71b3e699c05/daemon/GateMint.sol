// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract GateMint {
    uint160 public constant TARGET_FLAGS = 0x00C8;
    uint160 public constant FLAG_MASK    = 0x3FFF;

    event GateMinted(address indexed gate, bytes32 indexed salt);

    error MineFailed();
    error MintFailed();

    function mineMint(
        bytes calldata creationCodeWithArgs,
        bytes32 seed,
        uint256 maxIterations
    ) external returns (address gate, bytes32 salt) {
        bytes32 codeHash = keccak256(creationCodeWithArgs);
        for (uint256 i = 0; i < maxIterations; i++) {
            bytes32 candidate = keccak256(abi.encode(seed, i));
            address predicted = _predict(candidate, codeHash);
            if (uint160(predicted) & FLAG_MASK == TARGET_FLAGS) {
                salt = candidate;
                gate = _cast(salt, creationCodeWithArgs);
                return (gate, salt);
            }
        }
        revert MineFailed();
    }

    function mintWithSalt(bytes32 salt, bytes calldata creationCodeWithArgs)
        external returns (address gate)
    {
        gate = _cast(salt, creationCodeWithArgs);
    }

    function predictMint(bytes32 salt, bytes32 codeHash) external view returns (address) {
        return _predict(salt, codeHash);
    }

    function flagsOk(address addr) external pure returns (bool) {
        return uint160(addr) & FLAG_MASK == TARGET_FLAGS;
    }

    function _predict(bytes32 salt, bytes32 codeHash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), salt, codeHash
        )))));
    }

    function _cast(bytes32 salt, bytes calldata creationCodeWithArgs)
        internal returns (address gate)
    {
        assembly {
            let p := mload(0x40)
            calldatacopy(p, creationCodeWithArgs.offset, creationCodeWithArgs.length)
            gate := create2(0, p, creationCodeWithArgs.length, salt)
        }
        if (gate == address(0)) revert MintFailed();
        emit GateMinted(gate, salt);
    }
}
