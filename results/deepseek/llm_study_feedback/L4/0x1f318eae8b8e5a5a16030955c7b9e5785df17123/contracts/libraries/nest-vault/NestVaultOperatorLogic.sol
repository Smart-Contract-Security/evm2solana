// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title  NestVaultOperatorLogic
/// @notice Library containing operator-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultOperatorLogic {
    // Define the storage struct locally since the import is missing
    struct NestVaultCoreStorage {
        mapping(address => mapping(address => bool)) isVaultOperator;
        mapping(address => mapping(bytes32 => bool)) authorizations;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error SelfOperator();
    error DeadlineExpired();
    error NonceAlreadyUsed();
    error ERC7540InvalidSigner();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when an operator is set or revoked
    /// @param controller address The controller setting the operator
    /// @param operator   address The operator being set
    /// @param approved   bool    Whether the operator is approved
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the setOperator logic
    /// @param  $         NestVaultCoreStorage The full storage struct
    /// @param  _operator address The operator address
    /// @param  _approved bool    Whether to approve or revoke
    /// @param  _caller   address The caller (msg.sender)
    /// @return _success  bool    Always returns true on success
    function executeSetOperator(
        NestVaultCoreStorage storage $,
        address _operator,
        bool _approved,
        address _caller
    ) external returns (bool _success) {
        validateSetOperator($, _operator, _caller);
        $.isVaultOperator[_caller][_operator] = _approved;
        emit OperatorSet(_caller, _operator, _approved);
        return true;
    }

    /// @notice Validates and executes an operator authorization
    /// @dev    Validates inputs, verifies via EIP712 signatures, and updates state
    /// @param  $                NestVaultCoreStorage The full storage struct
    /// @param  _controller       address The controller's address
    /// @param  _operator         address The operator's address
    /// @param  _approved         bool    Whether the operator is approved or not
    /// @param  _nonce            bytes32 A unique identifier for the authorization
    /// @param  _deadline         uint256 The deadline for the authorization
    /// @param  _signature        bytes   The signature to validate the authorization
    /// @param  _domainSeparator  bytes32 The EIP712 domain separator
    /// @return _success          bool    Always returns true on success
    function executeAuthorizeOperator(
        NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature,
        bytes32 _domainSeparator
    ) external returns (bool _success) {
        validateAuthorizeOperator($, _controller, _operator, _nonce, _deadline);

        bytes32 _structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                _controller,
                _operator,
                _approved,
                _nonce,
                _deadline
            )
        );

        bytes32 _hash = MessageHashUtils.toTypedDataHash(_domainSeparator, _structHash);

        if (!isValidSignatureNow(_controller, _hash, _signature)) {
            revert ERC7540InvalidSigner();
        }

        $.authorizations[_controller][_nonce] = true;
        $.isVaultOperator[_controller][_operator] = _approved;
        emit OperatorSet(_controller, _operator, _approved);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates the setOperator call
    /// @param $         NestVaultCoreStorage The storage struct
    /// @param _operator address The operator address
    /// @param _caller   address The caller address
    function validateSetOperator(
        NestVaultCoreStorage storage $,
        address _operator,
        address _caller
    ) internal view {
        if (_operator == address(0)) {
            revert ZeroAddress();
        }
        if (_caller == _operator) {
            revert SelfOperator();
        }
    }

    /// @notice Validates the authorizeOperator call
    /// @param $          NestVaultCoreStorage The storage struct
    /// @param _controller address The controller address
    /// @param _operator   address The operator address
    /// @param _nonce      bytes32 The nonce
    /// @param _deadline   uint256 The deadline
    function validateAuthorizeOperator(
        NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bytes32 _nonce,
        uint256 _deadline
    ) internal view {
        if (_controller == address(0)) {
            revert ZeroAddress();
        }
        if (_operator == address(0)) {
            revert ZeroAddress();
        }
        if (block.timestamp > _deadline) {
            revert DeadlineExpired();
        }
        if ($.authorizations[_controller][_nonce]) {
            revert NonceAlreadyUsed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        SIGNATURE VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies that a signature is valid for a given signer and data hash
    /// @param signer   The address that supposedly signed the data
    /// @param hash     The hash of the data that was signed
    /// @param signature The signature to verify
    /// @return bool Whether the signature is valid
    function isValidSignatureNow(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        (address recovered, ) = _recoverSigner(hash, signature);
        return recovered == signer;
    }

    /// @notice Recovers the signer address from a hash and signature
    /// @param hash      The hash of the signed data
    /// @param signature The signature bytes
    /// @return signer   The recovered signer address
    /// @return err      Any error that occurred during recovery
    function _recoverSigner(bytes32 hash, bytes memory signature) private pure returns (address signer, bool err) {
        // Check signature length
        if (signature.length != 65) {
            return (address(0), true);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        /// @solidity memory-safe-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // If the version is incorrect, try the recovery
        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            return (address(0), true);
        } else {
            // ecrecover returns address(0) on error
            signer = ecrecover(hash, v, r, s);
            if (signer == address(0)) {
                return (address(0), true);
            }
            return (signer, false);
        }
    }
}