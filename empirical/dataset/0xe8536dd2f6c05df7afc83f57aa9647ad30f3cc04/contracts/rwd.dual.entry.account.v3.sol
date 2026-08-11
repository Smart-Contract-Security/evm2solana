// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IEntryPoint {}

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

contract RewardyDualEntryAccountV3 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;
    bytes4 internal constant EIP1271_SUCCESS = 0x1626ba7e;
    bytes4 internal constant EIP1271_FAILED = 0xffffffff;

    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 internal constant ERC1271_INTERFACE_ID = 0x1626ba7e;
    bytes4 internal constant ERC721_RECEIVER_ID = 0x150b7a02;
    bytes4 internal constant ERC1155_RECEIVER_ID = 0x4e2312e0;
    bytes4 internal constant ERC1155_SINGLE_RECEIVED = 0xf23a6e61;
    bytes4 internal constant ERC1155_BATCH_RECEIVED = 0xbc197c81;

    bytes4 internal constant IS_PAUSED_SELECTOR = 0xb187bd26;
    uint256 internal constant MAX_REVERT_DATA = 1024;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 private constant NAME_HASH = keccak256("RewardyDualEntryAccount");
    bytes32 private constant VERSION_HASH = keccak256("3.4");

    bytes32 private constant CALL_TYPEHASH =
        keccak256("Call(address to,uint256 value,bytes data)");

    bytes32 private constant EXECUTE_TYPEHASH =
        keccak256(
            "Execute(Call[] calls,uint256 msgValue,address feeToken,uint256 feeAmount,address feeReceiver,uint256 nonce,uint256 deadline)Call(address to,uint256 value,bytes data)"
        );

    bytes32 private constant PERSONAL_SIGN_TYPEHASH =
        keccak256("PersonalSign(bytes32 prefixedHash)");

    bytes32 private constant USEROP_VALIDATION_TYPEHASH =
        keccak256(
            "UserOpValidation(bytes32 userOpHash,uint48 validUntil,uint48 validAfter)"
        );

    /// @custom:storage-location erc7201:rewardy.dualentry.storage
    struct AccountStorage {
        uint256 nonce;
        bool locked;
        uint256 nonce4337;
    }

    bytes32 private constant STORAGE_SLOT =
        0xcc666bc151a493253ef3c495dcbd5c23a000d3c5e2ec20b9d08425abf39d6b00;

    function _getStorage() private pure returns (AccountStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    IEntryPoint public immutable ENTRY_POINT;
    address public immutable PAUSE_BEACON;

    struct BatchCall {
        address target;
        uint256 value;
        bytes data;
    }

    struct InternalCall {
        address to;
        uint256 value;
        bytes data;
    }

    struct Fee {
        address token;
        uint256 amount;
        address receiver;
    }

    event CallExecuted(address indexed to, uint256 value, bytes data);
    event BatchExecuted(
        uint256 indexed nonceUsed,
        uint256 callCount,
        bytes32 callsStructHash
    );
    event FeeCharged(address indexed token, address indexed to, uint256 amount);

    error OnlyEntryPoint();
    error Reentrancy();
    error ExpiredDeadline();
    error InvalidSignature();
    error SelfCallForbidden();
    error EntryPointCallForbidden();
    error InvalidFeeReceiver();
    error InvalidFeeToken();
    error FeePaymentFailed();
    error SystemPaused();
    error CallReverted();
    error InvalidSender();

    modifier onlyEP() {
        if (msg.sender != address(ENTRY_POINT)) revert OnlyEntryPoint();
        _;
    }

    modifier nonReentrant() {
        AccountStorage storage s = _getStorage();
        if (s.locked) revert Reentrancy();
        s.locked = true;
        _;
        s.locked = false;
    }

    modifier whenNotPaused() {
        if (_isPaused()) revert SystemPaused();
        _;
    }

    constructor(address entryPoint_, address pauseBeacon_) {
        require(entryPoint_ != address(0), "EP=0");
        require(pauseBeacon_ != address(0), "Beacon=0");
        require(entryPoint_.code.length > 0, "EP:noCode");
        require(pauseBeacon_.code.length > 0, "Beacon:noCode");

        ENTRY_POINT = IEntryPoint(entryPoint_);
        PAUSE_BEACON = pauseBeacon_;
    }

    /// @dev Fail-open: returns false if beacon reverts or has no code.
    function _isPaused() internal view returns (bool paused) {
        address beacon = PAUSE_BEACON;
        bytes4 selector = IS_PAUSED_SELECTOR;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, selector)
            let success := staticcall(gas(), beacon, ptr, 4, ptr, 32)
            if and(success, gt(returndatasize(), 31)) {
                paused := iszero(iszero(mload(ptr)))
            }
        }
    }

    function _domainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    NAME_HASH,
                    VERSION_HASH,
                    block.chainid,
                    address(this)
                )
            );
    }

    function _hashTypedData(
        bytes32 structHash
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", _domainSeparator(), structHash)
            );
    }

    function _packValidationData(
        bool sigFailed,
        uint48 validUntil,
        uint48 validAfter
    ) internal pure returns (uint256) {
        return
            (sigFailed ? 1 : 0) |
            (uint256(validUntil) << 160) |
            (uint256(validAfter) << 208);
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            assembly {
                pop(call(gas(), caller(), missingAccountFunds, 0, 0, 0, 0))
            }
        }
    }

    // ─── ERC-4337 Path ───────────────────────────────────────────

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable onlyEP nonReentrant whenNotPaused {
        InternalCall[] memory calls = new InternalCall[](1);
        calls[0] = InternalCall({to: target, value: value, data: data});
        _executeBatch4337(calls);
    }

    function executeBatch(
        BatchCall[] calldata calls_
    ) external payable onlyEP nonReentrant whenNotPaused {
        InternalCall[] memory calls = new InternalCall[](calls_.length);
        for (uint256 i = 0; i < calls_.length; i++) {
            calls[i] = InternalCall({
                to: calls_[i].target,
                value: calls_[i].value,
                data: calls_[i].data
            });
        }
        _executeBatch4337(calls);
    }

    /// @notice Validates a 4337 UserOperation.
    /// @dev Signature format:
    ///   65 bytes — ECDSA(wrappedHash), no expiry
    ///   77 bytes — ECDSA(wrappedHash) ‖ uint48 validUntil ‖ uint48 validAfter
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEP returns (uint256 validationData) {
        if (_isPaused()) revert SystemPaused();
        if (userOp.sender != address(this)) revert InvalidSender();

        uint256 sigLen = userOp.signature.length;
        bytes calldata ecdsaSig;
        uint48 validUntil;
        uint48 validAfter;

        if (sigLen == 65) {
            ecdsaSig = userOp.signature;
            validUntil = 0;
            validAfter = 0;
        } else if (sigLen == 77) {
            ecdsaSig = userOp.signature[:65];
            bytes calldata rawSig = userOp.signature;
            assembly {
                validUntil := shr(208, calldataload(add(rawSig.offset, 65)))
                validAfter := shr(208, calldataload(add(rawSig.offset, 71)))
            }
            if (validUntil != 0 && validAfter >= validUntil) {
                _payPrefund(missingAccountFunds);
                return _packValidationData(true, 0, 0);
            }
        } else {
            _payPrefund(missingAccountFunds);
            return _packValidationData(true, 0, 0);
        }

        bytes32 wrappedHash = _hashTypedData(
            keccak256(
                abi.encode(
                    USEROP_VALIDATION_TYPEHASH,
                    userOpHash,
                    validUntil,
                    validAfter
                )
            )
        );

        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(
            wrappedHash,
            ecdsaSig
        );
        bool sigFailed = (err != ECDSA.RecoverError.NoError ||
            recovered != address(this));

        _payPrefund(missingAccountFunds);
        return _packValidationData(sigFailed, validUntil, validAfter);
    }

    // ─── EIP-7702 Path ───────────────────────────────────────────

    function executeWithAuthorization(
        InternalCall[] calldata calls,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        _verifyAndExecute(
            calls,
            Fee(address(0), 0, address(0)),
            deadline,
            signature
        );
    }

    function executeWithFee(
        InternalCall[] calldata calls,
        Fee calldata fee,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        _verifyAndExecute(calls, fee, deadline, signature);
    }

    function _verifyAndExecute(
        InternalCall[] calldata calls,
        Fee memory fee,
        uint256 deadline,
        bytes calldata signature
    ) internal {
        if (block.timestamp > deadline) revert ExpiredDeadline();

        AccountStorage storage s = _getStorage();
        bytes32 callsStructHash = _hashCallsTyped(calls);

        bytes32 digest = _hashTypedData(
            keccak256(
                abi.encode(
                    EXECUTE_TYPEHASH,
                    callsStructHash,
                    msg.value,
                    fee.token,
                    fee.amount,
                    fee.receiver,
                    s.nonce,
                    deadline
                )
            )
        );

        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(
            digest,
            signature
        );
        if (err != ECDSA.RecoverError.NoError || recovered != address(this)) {
            revert InvalidSignature();
        }

        uint256 usedNonce = s.nonce;
        unchecked {
            s.nonce = usedNonce + 1;
        }

        if (fee.amount > 0) {
            if (
                fee.receiver == address(0) ||
                fee.receiver == address(this) ||
                fee.receiver == address(ENTRY_POINT)
            ) revert InvalidFeeReceiver();
            if (fee.token == address(this) || fee.token == address(ENTRY_POINT))
                revert InvalidFeeToken();

            if (fee.token == address(0)) {
                (bool ok, ) = payable(fee.receiver).call{value: fee.amount}("");
                if (!ok) revert FeePaymentFailed();
            } else {
                IERC20(fee.token).safeTransfer(fee.receiver, fee.amount);
            }
            emit FeeCharged(fee.token, fee.receiver, fee.amount);
        }

        _executeBatchNoNonce(calls, usedNonce, callsStructHash);
    }

    // ─── Batch Executors ─────────────────────────────────────────

    function _executeBatch4337(InternalCall[] memory calls) internal {
        AccountStorage storage s = _getStorage();
        uint256 n = s.nonce4337;
        unchecked {
            s.nonce4337 = n + 1;
        }
        _executeBatchNoNonce(calls, n, _hashCallsMemoryStructural(calls));
    }

    function _executeBatchNoNonce(
        InternalCall[] memory calls,
        uint256 nonceForEvent,
        bytes32 callsStructHash
    ) internal {
        address ep = address(ENTRY_POINT);
        uint256 len = calls.length;
        for (uint256 i = 0; i < len; i++) {
            if (calls[i].to == address(this)) revert SelfCallForbidden();
            if (calls[i].to == ep) revert EntryPointCallForbidden();

            bool ok;
            bytes memory data = calls[i].data;
            address to = calls[i].to;
            uint256 val = calls[i].value;
            assembly {
                ok := call(gas(), to, val, add(data, 0x20), mload(data), 0, 0)
            }

            if (!ok) {
                uint256 rdz;
                assembly {
                    rdz := returndatasize()
                }
                if (rdz > MAX_REVERT_DATA) revert CallReverted();
                assembly {
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0, rdz)
                    revert(ptr, rdz)
                }
            }
            emit CallExecuted(to, val, data);
        }
        emit BatchExecuted(nonceForEvent, len, callsStructHash);
    }

    // ─── EIP-712 Hashing ─────────────────────────────────────────
    // INVARIANT: both functions MUST produce identical output for identical input.

    function _hashCallsTyped(
        InternalCall[] calldata calls
    ) internal pure returns (bytes32) {
        uint256 len = calls.length;
        bytes32[] memory hashes = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    CALL_TYPEHASH,
                    calls[i].to,
                    calls[i].value,
                    keccak256(calls[i].data)
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _hashCallsMemoryStructural(
        InternalCall[] memory calls
    ) internal pure returns (bytes32) {
        uint256 len = calls.length;
        bytes32[] memory hashes = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    CALL_TYPEHASH,
                    calls[i].to,
                    calls[i].value,
                    keccak256(calls[i].data)
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    // ─── View ────────────────────────────────────────────────────

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }
    function version() external pure returns (string memory) {
        return "3.4";
    }
    function entryPoint() external view returns (IEntryPoint) {
        return ENTRY_POINT;
    }
    function getNonce() external view returns (uint256) {
        return _getStorage().nonce;
    }
    function getNonce4337() external view returns (uint256) {
        return _getStorage().nonce4337;
    }
    function isPaused() external view returns (bool) {
        return _isPaused();
    }

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory ver,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (
            hex"0f",
            "RewardyDualEntryAccount",
            "3.4",
            block.chainid,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    // ─── ERC-1271 ────────────────────────────────────────────────

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        bytes32 digest = _hashTypedData(
            keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, hash))
        );
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(
            digest,
            signature
        );
        if (err != ECDSA.RecoverError.NoError) return EIP1271_FAILED;
        return recovered == address(this) ? EIP1271_SUCCESS : EIP1271_FAILED;
    }

    // ─── Interface Support ───────────────────────────────────────

    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return
            interfaceId == ERC165_INTERFACE_ID ||
            interfaceId == ERC1271_INTERFACE_ID ||
            interfaceId == ERC721_RECEIVER_ID ||
            interfaceId == ERC1155_RECEIVER_ID;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return ERC721_RECEIVER_ID;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return ERC1155_SINGLE_RECEIVED;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return ERC1155_BATCH_RECEIVED;
    }

    receive() external payable {}
    fallback() external payable {}
}