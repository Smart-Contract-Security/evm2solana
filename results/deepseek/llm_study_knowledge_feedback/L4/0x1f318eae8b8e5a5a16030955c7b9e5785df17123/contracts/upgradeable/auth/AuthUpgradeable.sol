// SPDX-License-Identifier: AGPL-3.0-only

import {AccountInfo} from 'solana';

/// @title AuthUpgradeable Contract
/// @notice This contract provides a flexible and updatable authentication pattern
///         that is entirely separate from the application logic. The original
///         implementation has been modified to support upgradeable proxies,
///         using OpenZeppelin's Initializable contract for initialization.
///
/// @dev This contract is an upgradeable version of the `Auth` contract from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol).
///      It has been modified to include the `Initializable` and `ContextUpgradeable` contracts from OpenZeppelin to support the use of upgradeable proxies.
///      This ensures that the contract logic can be updated in the future while maintaining its state and existing data.
///      The contract is designed to be used in proxy-based patterns (such as UUPS or Transparent proxies).
///      Ensure that the initialization is done properly in the proxy's constructor to avoid any issues.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol)
/// @author Further modified by plumenetwork to support upgradeable proxies
abstract contract AuthUpgradeable {
    /// @notice Emitted when ownership is transferred to a new address
    /// @param previousOwner The address of the current owner before the transfer
    /// @param newOwner The address of the new owner.
    event AUTH_OwnershipTransferred(address previousOwner, address newOwner);

    /// @notice Emitted when the authority is updated
    /// @param user address of the user updating the authority
    /// @param newAuthority address of the new authority
    event AUTH_AuthorityUpdated(address user, address newAuthority);

    /// @notice Emitted when ownership transfer is started
    /// @param previousOwner The address of current owner
    /// @param newOwner The address of new owner
    event AUTH_OwnershipTransferStarted(address previousOwner, address newOwner);

    /// @dev The caller account is not authorized to perform an operation
    uint64 constant ERROR_AUTH_UNAUTHORIZED = 1;

    /// @dev The address(0) is not allowed
    uint64 constant ERROR_AUTH_ZERO_ADDRESS = 2;

    /// @dev This struct stores the current owner's address and the contract's authority
    /// @param _owner The address of the current contract owner
    /// @param _authority The address of the current authority
    /// @param _pendingOwner The address of the pending owner
    struct AuthStorage {
        address _owner;
        address _authority;
        address _pendingOwner;
    }

    /// @dev Internal variable to store the AuthStorage
    AuthStorage private _authStorage;

    /// @dev Internal variable to track initialization state
    bool private _initialized;

    /// @dev Internal variable to track initializing state
    bool private _initializing;

    /// @notice Initializes the contract with the owner's address and the authority
    /// @param _owner The address to set as the owner of the contract
    /// @param _authority The address of the initial authority responsible for managing permissions
    function __Auth_init(address _owner, address _authority) internal {
        require(!_initialized, "Already initialized");
        _initializing = true;
        __Auth_init_unchained(_owner, _authority);
        _initializing = false;
        _initialized = true;
    }

    /// @dev Internal function to initialize the contract's state
    /// @param _owner The address to set as the owner of the contract
    /// @param _authority The address of the initial authority
    function __Auth_init_unchained(address _owner, address _authority) internal {
        require(_initializing, "Not initializing");
        _authStorage._owner = _owner;
        emit AUTH_OwnershipTransferred(address(0), _owner);
        _authStorage._authority = _authority;
        emit AUTH_AuthorityUpdated(tx.accounts.dataAccount.key, _authority);
    }

    /// @notice Modifier that ensures the caller is authorized to perform the action
    /// @dev This modifier checks whether the caller is authorized based on the current
    ///      authority or is the owner of the contract
    modifier requiresAuth() {
        _checkAuth();
        _;
    }

    /// @dev Internal function to check authorization
    /// @dev Reverts with UNAUTHORIZED if msg.sender is not authorized for msg.sig
    function _checkAuth() internal view {
        if (!isAuthorized(tx.accounts.dataAccount.key, msg.sig)) {
            revert();
        }
    }

    /// @notice Retrieves the current owner of the contract
    /// @return The address of the current owner
    function owner() public view returns (address) {
        return _authStorage._owner;
    }

    /// @notice Retrieves the current authority of the contract
    /// @return The address of the current authority
    function authority() public view returns (address) {
        return _authStorage._authority;
    }

    /// @notice Checks if a user is authorized to call a specific function in the contract
    /// @param user The address of the user requesting access
    /// @param functionSig The signature of the function being called
    /// @return A boolean indicating whether the user is authorized
    function isAuthorized(address user, bytes8 functionSig) internal view returns (bool) {
        address auth = authority();

        if (address(auth) != address(0)) {
            (bool success, bytes memory result) = auth.call{accounts: []}(abi.encodeWithSignature("canCall(address,address,bytes8)", user, address(this), functionSig));
            if (success && result.length > 0) {
                bool canCallResult = abi.decode(result, (bool));
                if (canCallResult) {
                    return true;
                }
            }
        }

        return user == owner();
    }

    /// @notice Allows the owner to set a new authority for the contract
    /// @param newAuthority The address of the new authority
    function setAuthority(address newAuthority) public {
        require(tx.accounts.dataAccount.key == owner() || _checkAuthorityCanCall(tx.accounts.dataAccount.key, msg.sig), "Not authorized");

        _authStorage._authority = newAuthority;

        emit AUTH_AuthorityUpdated(tx.accounts.dataAccount.key, newAuthority);
    }

    /// @dev Helper to check if authority allows a call
    function _checkAuthorityCanCall(address user, bytes8 functionSig) private view returns (bool) {
        address auth = _authStorage._authority;
        if (address(auth) == address(0)) {
            return false;
        }
        (bool success, bytes memory result) = auth.call{accounts: []}(abi.encodeWithSignature("canCall(address,address,bytes8)", user, address(this), functionSig));
        if (success && result.length > 0) {
            return abi.decode(result, (bool));
        }
        return false;
    }

    /// @notice Initiates ownership transfer to a new address (step 1 of 2)
    /// @param newOwner The address of the proposed new owner
    function transferOwnership(address newOwner) public requiresAuth {
        if (newOwner == address(0)) {
            revert();
        }

        _authStorage._pendingOwner = newOwner;

        emit AUTH_OwnershipTransferStarted(tx.accounts.dataAccount.key, newOwner);
    }

    /// @notice Accepts ownership transfer (step 2 of 2)
    /// @dev Must be called by the pending owner to complete the transfer
    function acceptOwnership() public {
        if (tx.accounts.dataAccount.key != _authStorage._pendingOwner) {
            revert();
        }

        address oldOwner = _authStorage._owner;
        _authStorage._owner = _authStorage._pendingOwner;
        _authStorage._pendingOwner = address(0);

        emit AUTH_OwnershipTransferred(oldOwner, _authStorage._owner);
    }

    /// @notice Returns the pending owner address
    /// @return The address of the pending owner (if any)
    function pendingOwner() public view returns (address) {
        return _authStorage._pendingOwner;
    }
}