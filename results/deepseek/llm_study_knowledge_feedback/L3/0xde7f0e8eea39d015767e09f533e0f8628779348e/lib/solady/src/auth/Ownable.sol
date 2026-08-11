// SPDX-License-Identifier: MIT

/// @notice Simple single owner authorization mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/auth/Ownable.sol)
///
/// @dev Note:
/// This implementation does NOT auto-initialize the owner to `msg.sender`.
/// You MUST call the `_initializeOwner` in the constructor / initializer.
///
/// While the ownable portion follows
/// [EIP-173](https://eips.ethereum.org/EIPS/eip-173) for compatibility,
/// the nomenclature for the 2-step ownership handover may be unique to this codebase.
abstract contract Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The caller is not authorized to call the function.
    // Error definitions are not yet working for Solana.
    // error Unauthorized();
    // error NewOwnerIsZeroAddress();
    // error NoHandoverRequest();
    // error AlreadyInitialized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ownership is transferred from `oldOwner` to `newOwner`.
    /// This event is intentionally kept the same as OpenZeppelin's Ownable to be
    /// compatible with indexers and [EIP-173](https://eips.ethereum.org/EIPS/eip-173),
    /// despite it not being as lightweight as a single argument event.
    event OwnershipTransferred(address oldOwner, address newOwner);

    /// @dev An ownership handover to `pendingOwner` has been requested.
    event OwnershipHandoverRequested(address pendingOwner);

    /// @dev The ownership handover to `pendingOwner` has been canceled.
    event OwnershipHandoverCanceled(address pendingOwner);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The owner slot is given by:
    /// `bytes32(~uint256(uint32(bytes4(keccak256("_OWNER_SLOT_NOT")))))`.
    /// It is intentionally chosen to be a high value
    /// to avoid collision with lower slots.
    /// The choice of manual storage layout is to enable compatibility
    /// with both regular and upgradeable contracts.
    bytes32 internal constant _OWNER_SLOT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff74873927;

    /// The ownership handover slot of `newOwner` is given by:
    /// ```
    ///     mstore(0x00, or(shl(96, user), _HANDOVER_SLOT_SEED))
    ///     let handoverSlot := keccak256(0x00, 0x20)
    /// ```
    /// It stores the expiry timestamp of the two-step ownership handover.
    uint256 private constant _HANDOVER_SLOT_SEED = 0x389a75e1;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Override to return true to make `_initializeOwner` prevent double-initialization.
    function _guardInitializeOwner() internal pure virtual returns (bool guard) {}

    /// @dev Initializes the owner directly without authorization guard.
    /// This function must be called upon initialization,
    /// regardless of whether the contract is upgradeable or not.
    /// This is to enable generalization to both regular and upgradeable contracts,
    /// and to save gas in case the initial owner is not the caller.
    /// For performance reasons, this function will not check if there
    /// is an existing owner.
    function _initializeOwner(address newOwner) internal virtual {
        if (_guardInitializeOwner()) {
            bytes32 ownerSlot = _OWNER_SLOT;
            address currentOwner = address(uint160(uint256(_getStorage(ownerSlot))));
            if (currentOwner != address(0)) {
                revert("AlreadyInitialized");
            }
            // Clean the upper 96 bits.
            newOwner = address(uint160(uint256(uint160(newOwner))));
            // Store the new value.
            _setStorage(ownerSlot, bytes32(uint256(uint160(newOwner))));
            // Emit the {OwnershipTransferred} event.
            emit OwnershipTransferred(address(0), newOwner);
        } else {
            // Clean the upper 96 bits.
            newOwner = address(uint160(uint256(uint160(newOwner))));
            // Store the new value.
            _setStorage(_OWNER_SLOT, bytes32(uint256(uint160(newOwner))));
            // Emit the {OwnershipTransferred} event.
            emit OwnershipTransferred(address(0), newOwner);
        }
    }

    /// @dev Sets the owner directly without authorization guard.
    function _setOwner(address newOwner) internal virtual {
        bytes32 ownerSlot = _OWNER_SLOT;
        // Clean the upper 96 bits.
        newOwner = address(uint160(uint256(uint160(newOwner))));
        address oldOwner = address(uint160(uint256(_getStorage(ownerSlot))));
        // Emit the {OwnershipTransferred} event.
        emit OwnershipTransferred(oldOwner, newOwner);
        // Store the new value.
        _setStorage(ownerSlot, bytes32(uint256(uint160(newOwner))));
    }

    /// @dev Throws if the sender is not the owner.
    function _checkOwner() internal view virtual {
        if (tx.accounts.dataAccount.key != address(uint160(uint256(_getStorage(_OWNER_SLOT))))) {
            revert("Unauthorized");
        }
    }

    /// @dev Returns how long a two-step ownership handover is valid for in seconds.
    /// Override to return a different value if needed.
    /// Made internal to conserve bytecode. Wrap it in a public function if needed.
    function _ownershipHandoverValidFor() internal view virtual returns (uint64) {
        return 48 * 3600;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Allows the owner to transfer the ownership to `newOwner`.
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert("NewOwnerIsZeroAddress");
        }
        _setOwner(newOwner);
    }

    /// @dev Allows the owner to renounce their ownership.
    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    /// @dev Request a two-step ownership handover to the caller.
    /// The request will automatically expire in 48 hours (172800 seconds) by default.
    function requestOwnershipHandover() public virtual {
        unchecked {
            uint64 expires = block.timestamp + _ownershipHandoverValidFor();
            // Compute and set the handover slot to `expires`.
            bytes32 handoverSlot = keccak256(abi.encodePacked(_HANDOVER_SLOT_SEED, tx.accounts.dataAccount.key));
            _setStorage(handoverSlot, bytes32(uint256(expires)));
            // Emit the {OwnershipHandoverRequested} event.
            emit OwnershipHandoverRequested(tx.accounts.dataAccount.key);
        }
    }

    /// @dev Cancels the two-step ownership handover to the caller, if any.
    function cancelOwnershipHandover() public virtual {
        // Compute and set the handover slot to 0.
        bytes32 handoverSlot = keccak256(abi.encodePacked(_HANDOVER_SLOT_SEED, tx.accounts.dataAccount.key));
        _setStorage(handoverSlot, bytes32(uint256(0)));
        // Emit the {OwnershipHandoverCanceled} event.
        emit OwnershipHandoverCanceled(tx.accounts.dataAccount.key);
    }

    /// @dev Allows the owner to complete the two-step ownership handover to `pendingOwner`.
    /// Reverts if there is no existing ownership handover requested by `pendingOwner`.
    function completeOwnershipHandover(address pendingOwner) public virtual onlyOwner {
        // Compute and set the handover slot to 0.
        bytes32 handoverSlot = keccak256(abi.encodePacked(_HANDOVER_SLOT_SEED, pendingOwner));
        uint64 handoverExpiry = uint64(uint256(_getStorage(handoverSlot)));
        // If the handover does not exist, or has expired.
        if (handoverExpiry == 0 || block.timestamp > handoverExpiry) {
            revert("NoHandoverRequest");
        }
        // Set the handover slot to 0.
        _setStorage(handoverSlot, bytes32(uint256(0)));
        _setOwner(pendingOwner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the owner of the contract.
    function owner() public view virtual returns (address result) {
        result = address(uint160(uint256(_getStorage(_OWNER_SLOT))));
    }

    /// @dev Returns the expiry timestamp for the two-step ownership handover to `pendingOwner`.
    function ownershipHandoverExpiresAt(address pendingOwner)
        public
        view
        virtual
        returns (uint64 result)
    {
        // Compute the handover slot.
        bytes32 handoverSlot = keccak256(abi.encodePacked(_HANDOVER_SLOT_SEED, pendingOwner));
        // Load the handover slot.
        result = uint64(uint256(_getStorage(handoverSlot)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Marks a function as only callable by the owner.
    modifier onlyOwner() virtual {
        _checkOwner();
        _;
    }

    /// @dev Helper to read from storage.
    function _getStorage(bytes32 slot) internal view virtual returns (bytes32 result) {
        // On Solana, we use a mapping to simulate storage slots.
        // The contract's data account stores a mapping from slot to value.
        // We use a simple approach: store values in a mapping.
        // Since we cannot use assembly sload/sstore, we use a mapping.
        result = _storage[slot];
    }

    /// @dev Helper to write to storage.
    function _setStorage(bytes32 slot, bytes32 value) internal virtual {
        _storage[slot] = value;
    }

    /// @dev Internal mapping to simulate storage slots on Solana.
    mapping(bytes32 => bytes32) private _storage;
}