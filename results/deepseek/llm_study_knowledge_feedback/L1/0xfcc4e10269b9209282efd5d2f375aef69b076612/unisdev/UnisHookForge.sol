// SPDX-License-Identifier: MIT

import 'solana';

/// @title UnisHookForge - CREATE2 deployer for the shared UnisHook
/// @notice Target flag bits 0x00C8 = beforeSwap | afterSwap | beforeSwapReturnDelta.
///         An off-chain miner finds a salt whose predicted address satisfies
///         `addr & 0x3FFF == 0x00C8`. Either call `mineCast` to brute-force
///         the salt on-chain (gas-heavy, demo use only) or pass a salt found
///         off-chain into `castWithSalt`.
contract UnisHookForge {
    uint64 public constant TARGET_FLAGS = 0x00C8;
    uint64 public constant FLAG_MASK    = 0x3FFF;

    event HookForged(address indexed hook, bytes32 indexed salt);

    function mineCast(
        bytes calldata creationCodeWithArgs,
        bytes32 seed,
        uint64 maxIterations
    ) external returns (address hook, bytes32 salt) {
        bytes32 codeHash = keccak256(creationCodeWithArgs);
        for (uint64 i = 0; i < maxIterations; ) {
            bytes32 candidate = keccak256(abi.encode(seed, i));
            address predicted = _predict(candidate, codeHash);
            if (uint64(uint160(predicted)) & FLAG_MASK == TARGET_FLAGS) {
                salt = candidate;
                hook = _cast(salt, creationCodeWithArgs);
                return (hook, salt);
            }
            unchecked { i++; }
        }
        revert("MineFailed");
    }

    function castWithSalt(bytes32 salt, bytes calldata creationCodeWithArgs)
        external returns (address hook)
    {
        hook = _cast(salt, creationCodeWithArgs);
    }

    function predictAddress(bytes32 salt, bytes32 codeHash) external view returns (address) {
        return _predict(salt, codeHash);
    }

    function flagsOk(address addr) external pure returns (bool) {
        return uint64(uint160(addr)) & FLAG_MASK == TARGET_FLAGS;
    }

    function _predict(bytes32 salt, bytes32 codeHash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), salt, codeHash
        )))));
    }

    function _cast(bytes32 salt, bytes calldata creationCodeWithArgs)
        internal returns (address hook)
    {
        bytes memory code = creationCodeWithArgs;
        hook = address(new UnisHookForge{salt: salt}(code));
        if (hook == address(0)) revert("CreateFailed");
        emit HookForged(hook, salt);
    }
}