// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title NormlProfile
/// @notice Lightweight on-chain user profile registry for the NORML site.
/// @dev Stores a short handle and a raw RGB image blob per address. Image data
///      is stored as-is (no enforced format) and is expected to be a fixed-size
///      RGB byte string produced by the client (e.g. 100×100×3 = 30,000 bytes).
/// @author jiwa
contract NormlProfile {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Maximum allowed handle length in bytes.
    uint256 public constant MAX_HANDLE_BYTES = 32;

    /// @notice Maximum allowed image data length in bytes.
    /// @dev 40,000 bytes accommodates 100×100 RGB (30,000) plus headroom.
    uint256 public constant MAX_IMAGE_BYTES = 40_000;

    struct Profile {
        string handle;
        bytes imageData;
        uint64 updatedAt;
    }

    mapping(address => Profile) private _profiles;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event ProfileUpdated(address indexed user, string handle, uint256 imageBytes);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error HandleTooLong();
    error ImageTooLarge();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PUBLIC WRITE                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set caller's profile. Pass empty `handle` and/or `imageData` to clear that field.
    /// @param handle    Display name (≤ MAX_HANDLE_BYTES bytes).
    /// @param imageData Raw image bytes (≤ MAX_IMAGE_BYTES). Encoding is client-defined.
    function setProfile(string calldata handle, bytes calldata imageData) external {
        if (bytes(handle).length > MAX_HANDLE_BYTES) revert HandleTooLong();
        if (imageData.length > MAX_IMAGE_BYTES) revert ImageTooLarge();
        _profiles[msg.sender] = Profile({
            handle: handle,
            imageData: imageData,
            updatedAt: uint64(block.timestamp)
        });
        emit ProfileUpdated(msg.sender, handle, imageData.length);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PUBLIC READ                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Read a user's profile. Returns zero-valued fields if unset.
    function getProfile(address user)
        external
        view
        returns (string memory handle, bytes memory imageData, uint64 updatedAt)
    {
        Profile storage p = _profiles[user];
        return (p.handle, p.imageData, p.updatedAt);
    }

    /// @notice Return just the handle (cheaper for lookups).
    function getHandle(address user) external view returns (string memory) {
        return _profiles[user].handle;
    }
}
