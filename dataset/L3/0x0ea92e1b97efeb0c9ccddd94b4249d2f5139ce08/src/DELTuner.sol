// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DELData} from "./DELData.sol";
import {IDELDataStore} from "./DELDataStore.sol";

/// @dev Slim interface the tuner needs from the main DEL contract: token
/// ownership for access control, the per-token behaviour-set index for
/// default lookup, and the active dataStore address (which can be swapped
/// by the owner).
interface IDEL {
    function ownerOf(uint256 tokenId) external view returns (address);
    function behaviourIdxOf(uint256 tokenId) external view returns (uint8);
    function dataStore() external view returns (address);
    function emitMetadataUpdate(uint256 tokenId) external;
    function owner() external view returns (address);
}

/// @title DELTuner
/// @notice Holds per-token parameter overrides for the DEL collection.
/// Each of the 21 animation fields exposes its own owner-only setter.
/// All edits append to an on-chain tuning history. resetTune wipes the
/// overrides (and the "tuned" marker) but preserves the history.
contract DELTuner {
    // ---- canonical field indices (match BEHAVIOUR_FIELDS in encoder) ----
    uint8 public constant F_BASE_RADIUS           = 0;
    uint8 public constant F_ASPECT_RATIO          = 1;
    uint8 public constant F_STEP_SIZE             = 2;
    uint8 public constant F_MOVE_SPEED            = 3;
    uint8 public constant F_MAX_MOVE_DISTANCE     = 4;
    uint8 public constant F_X_BIAS                = 5;
    uint8 public constant F_Y_BIAS                = 6;
    uint8 public constant F_MIN_ROTATION_SPEED    = 7;
    uint8 public constant F_MAX_ROTATION_SPEED    = 8;
    uint8 public constant F_ROTATION_SMOOTHNESS   = 9;
    uint8 public constant F_MAX_ROTATION_ANGLE    = 10;
    uint8 public constant F_BASE_DEFORM_STRENGTH  = 11;
    uint8 public constant F_EXTRA_DEFORM_STRENGTH = 12;
    uint8 public constant F_DEFORM_FREQUENCY      = 13;
    uint8 public constant F_DEFORM_COMPLEXITY     = 14;
    uint8 public constant F_DEFORM_SMOOTHNESS     = 15;
    uint8 public constant F_DRIPPINESS            = 16;
    uint8 public constant F_TIME_SPEED            = 17;
    uint8 public constant F_PERSPECTIVE_DISTANCE  = 18;
    uint8 public constant F_PERSPECTIVE_STRENGTH  = 19;
    uint8 public constant F_BEHAVIOR_CHANGE_TIME  = 20;

    uint8 public constant FIELD_COUNT = 21;
    uint256 public constant MAX_PAGE_SIZE = 500;

    /// @notice Sentinel fieldIdx that marks a TuneRecord as a reset entry
    /// rather than a single-field tune. Lives outside the 0..FIELD_COUNT-1
    /// range so it can never collide with a real field. On a reset record:
    /// `oldValue` carries the bitmap of fields that were wiped, `newValue`
    /// is `0`. The frontend distinguishes reset entries by `fieldIdx == F_RESET`.
    uint8 public constant F_RESET = type(uint8).max;

    // Engine safety bound: deformComplexity is the count of harmonic terms;
    // the JS engine allocates Float32Arrays of this size at every render.
    // Anything < 1 makes the loop a no-op (visual death); anything > 16
    // wastes engine resources and starts to look incoherent. Bounds are
    // expressed in the same int32-scaled-by-SCALE form the rest of the
    // contract uses (so 1.0 == 10000, 16.0 == 160000).
    int32 public constant DEFORM_COMPLEXITY_MIN = 10000;
    int32 public constant DEFORM_COMPLEXITY_MAX = 160000;

    struct TuneRecord {
        uint48  blockNumber;
        address by;
        uint8   fieldIdx;
        int32   oldValue;
        int32   newValue;
    }

    error NotTokenOwner();
    error NotDelOwner();
    error ZeroAddress();
    error OutOfBounds(uint8 fieldIdx);
    error PageOutOfRange();
    error InvalidField(uint8 fieldIdx);

    event Tuned(
        uint256 indexed tokenId,
        address indexed by,
        uint8 fieldIdx,
        int32 oldValue,
        int32 newValue,
        uint256 blockNumber
    );
    event TuneReset(uint256 indexed tokenId, address indexed by, uint256 blockNumber);
    event DelUpdated(address oldDel, address newDel);

    /// @notice The DEL contract this tuner is bound to. Mutable by the
    /// current DEL owner so a small DEL upgrade does not force a tuner
    /// redeploy. Note: swapping `del` does NOT migrate per-token state
    /// already in this tuner — overrides and history stay attached to
    /// the same numeric tokenIds, which may now map to different owners
    /// on the new DEL. Plan accordingly.
    address public del;

    /// @dev Override value per (tokenId, fieldIdx). Only meaningful when the
    /// corresponding bit in `_overrideMask[tokenId]` is set.
    mapping(uint256 => mapping(uint8 => int32)) private _overrides;

    /// @dev 21-bit bitmap of which fields have been overridden for a token.
    /// `_overrideMask[t] == 0` is the "untuned" state.
    mapping(uint256 => uint32) private _overrideMask;

    mapping(uint256 => TuneRecord[]) private _tuneHistory;

    /// @dev The most recent `msg.sender` to call any setter on a given
    /// token. Cleared on resetTune. Surfaced on the SVG as "TUNED BY".
    mapping(uint256 => address) private _lastTunedBy;

    constructor(address _del) {
        if (_del == address(0)) revert ZeroAddress();
        del = _del;
    }

    /// @notice Re-point this tuner at a different DEL contract. Callable
    /// only by the current `del`'s owner. Emits `DelUpdated`.
    function setDel(address newDel) external {
        if (newDel == address(0)) revert ZeroAddress();
        if (msg.sender != IDEL(del).owner()) revert NotDelOwner();
        address old = del;
        del = newDel;
        emit DelUpdated(old, newDel);
    }

    // ------------------------------------------------------------ setters

    function setBaseRadius          (uint256 t, int32 v) external { _set(t, F_BASE_RADIUS, v); }
    function setAspectRatio         (uint256 t, int32 v) external { _set(t, F_ASPECT_RATIO, v); }
    function setStepSize            (uint256 t, int32 v) external { _set(t, F_STEP_SIZE, v); }
    function setMoveSpeed           (uint256 t, int32 v) external { _set(t, F_MOVE_SPEED, v); }
    function setMaxMoveDistance     (uint256 t, int32 v) external { _set(t, F_MAX_MOVE_DISTANCE, v); }
    function setXBias               (uint256 t, int32 v) external { _set(t, F_X_BIAS, v); }
    function setYBias               (uint256 t, int32 v) external { _set(t, F_Y_BIAS, v); }
    function setMinRotationSpeed    (uint256 t, int32 v) external { _set(t, F_MIN_ROTATION_SPEED, v); }
    function setMaxRotationSpeed    (uint256 t, int32 v) external { _set(t, F_MAX_ROTATION_SPEED, v); }
    function setRotationSmoothness  (uint256 t, int32 v) external { _set(t, F_ROTATION_SMOOTHNESS, v); }
    function setMaxRotationAngle    (uint256 t, int32 v) external { _set(t, F_MAX_ROTATION_ANGLE, v); }
    function setBaseDeformStrength  (uint256 t, int32 v) external { _set(t, F_BASE_DEFORM_STRENGTH, v); }
    function setExtraDeformStrength (uint256 t, int32 v) external { _set(t, F_EXTRA_DEFORM_STRENGTH, v); }
    function setDeformFrequency     (uint256 t, int32 v) external { _set(t, F_DEFORM_FREQUENCY, v); }
    function setDeformSmoothness    (uint256 t, int32 v) external { _set(t, F_DEFORM_SMOOTHNESS, v); }
    function setDrippiness          (uint256 t, int32 v) external { _set(t, F_DRIPPINESS, v); }
    function setTimeSpeed           (uint256 t, int32 v) external { _set(t, F_TIME_SPEED, v); }
    function setPerspectiveDistance (uint256 t, int32 v) external { _set(t, F_PERSPECTIVE_DISTANCE, v); }
    function setPerspectiveStrength (uint256 t, int32 v) external { _set(t, F_PERSPECTIVE_STRENGTH, v); }
    function setBehaviorChangeTime  (uint256 t, int32 v) external { _set(t, F_BEHAVIOR_CHANGE_TIME, v); }

    /// @notice The only field with engine-safety bounds. See DEFORM_COMPLEXITY_MIN/MAX.
    function setDeformComplexity(uint256 tokenId, int32 newValue) external {
        if (newValue < DEFORM_COMPLEXITY_MIN || newValue > DEFORM_COMPLEXITY_MAX) {
            revert OutOfBounds(F_DEFORM_COMPLEXITY);
        }
        _set(tokenId, F_DEFORM_COMPLEXITY, newValue);
    }

    /// @notice Wipe every override on `tokenId`. The "tuned" marker clears
    /// and the token reverts to its mint-time configuration. The tuning
    /// history is preserved (every prior tune stays readable), and a new
    /// reset entry is appended to history with `fieldIdx == F_RESET` and
    /// `oldValue` carrying the bitmap of fields that were wiped. Calling
    /// reset on an already-untuned token still emits the event but does
    /// not pollute history.
    function resetTune(uint256 tokenId) external {
        if (IDEL(del).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        uint32 mask = _overrideMask[tokenId];
        if (mask == 0) {
            // No-op but still emit so the action is observable.
            emit TuneReset(tokenId, msg.sender, block.number);
            return;
        }
        for (uint8 i = 0; i < FIELD_COUNT; i++) {
            if (mask & (uint32(1) << i) != 0) {
                delete _overrides[tokenId][i];
            }
        }
        delete _overrideMask[tokenId];
        delete _lastTunedBy[tokenId];
        _tuneHistory[tokenId].push(TuneRecord({
            blockNumber: uint48(block.number),
            by:          msg.sender,
            fieldIdx:    F_RESET,
            oldValue:    int32(uint32(mask)),
            newValue:    0
        }));
        emit TuneReset(tokenId, msg.sender, block.number);
        // EIP-4906: refresh marketplace metadata for this token.
        IDEL(del).emitMetadataUpdate(tokenId);
    }

    // ------------------------------------------------------------ views

    function isTuned(uint256 tokenId) external view returns (bool) {
        return _overrideMask[tokenId] != 0;
    }

    /// @notice The address that most recently called a setter on this
    /// token. Returns `address(0)` for untuned tokens (also after a
    /// `resetTune`). The SVG only renders the "TUNED BY" row when this
    /// is non-zero.
    function lastTunedBy(uint256 tokenId) external view returns (address) {
        return _lastTunedBy[tokenId];
    }

    function overrideMaskOf(uint256 tokenId) external view returns (uint32) {
        return _overrideMask[tokenId];
    }

    /// @notice Resolve one field's effective value (override if set, else default).
    /// Reverts if the token has not been minted (delegated to `ownerOf`).
    function effectiveField(uint256 tokenId, uint8 fieldIdx) public view returns (int32) {
        if (fieldIdx >= FIELD_COUNT) revert InvalidField(fieldIdx);
        IDEL(del).ownerOf(tokenId);
        if (_overrideMask[tokenId] & (uint32(1) << fieldIdx) != 0) {
            return _overrides[tokenId][fieldIdx];
        }
        return _defaultFor(tokenId, fieldIdx);
    }

    /// @notice Resolve all 21 effective field values for a token in one call.
    /// Renderers use this to avoid 21 separate STATICCALLs.
    /// Reverts if the token has not been minted (delegated to `ownerOf`).
    function effectiveFields(uint256 tokenId) external view returns (int32[21] memory out) {
        IDEL(del).ownerOf(tokenId);
        uint8 behaviourIdx = IDEL(del).behaviourIdxOf(tokenId);
        bytes memory defaults = IDELDataStore(IDEL(del).dataStore()).behaviourDefaults();
        uint32 mask = _overrideMask[tokenId];
        uint256 base = uint256(behaviourIdx) * FIELD_COUNT * 4;
        for (uint8 i = 0; i < FIELD_COUNT; i++) {
            if (mask & (uint32(1) << i) != 0) {
                out[i] = _overrides[tokenId][i];
            } else {
                out[i] = _readI32(defaults, base + uint256(i) * 4);
            }
        }
    }

    function getTuneCount(uint256 tokenId) external view returns (uint256) {
        return _tuneHistory[tokenId].length;
    }

    function getRecentTunes(uint256 tokenId) external view returns (TuneRecord[] memory) {
        TuneRecord[] storage history = _tuneHistory[tokenId];
        uint256 len = history.length;
        uint256 outLen = len > MAX_PAGE_SIZE ? MAX_PAGE_SIZE : len;
        TuneRecord[] memory out = new TuneRecord[](outLen);
        for (uint256 i = 0; i < outLen; i++) {
            out[i] = history[len - 1 - i];
        }
        return out;
    }

    function getTuneHistoryPage(uint256 tokenId, uint256 start, uint256 count)
        external
        view
        returns (TuneRecord[] memory)
    {
        TuneRecord[] storage history = _tuneHistory[tokenId];
        uint256 len = history.length;
        if (len == 0) return new TuneRecord[](0);
        if (start >= len) revert PageOutOfRange();
        if (count > MAX_PAGE_SIZE) count = MAX_PAGE_SIZE;
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 outLen = end > start ? end - start : 0;
        TuneRecord[] memory out = new TuneRecord[](outLen);
        for (uint256 i = 0; i < outLen; i++) {
            out[i] = history[start + i];
        }
        return out;
    }

    // ------------------------------------------------------------ internals

    function _set(uint256 tokenId, uint8 fieldIdx, int32 newValue) internal {
        if (IDEL(del).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        int32 oldValue;
        uint32 mask = _overrideMask[tokenId];
        if (mask & (uint32(1) << fieldIdx) != 0) {
            oldValue = _overrides[tokenId][fieldIdx];
        } else {
            oldValue = _defaultFor(tokenId, fieldIdx);
        }
        _overrides[tokenId][fieldIdx] = newValue;
        _overrideMask[tokenId] = mask | (uint32(1) << fieldIdx);
        _lastTunedBy[tokenId] = msg.sender;
        _tuneHistory[tokenId].push(TuneRecord({
            blockNumber: uint48(block.number),
            by:          msg.sender,
            fieldIdx:    fieldIdx,
            oldValue:    oldValue,
            newValue:    newValue
        }));
        emit Tuned(tokenId, msg.sender, fieldIdx, oldValue, newValue, block.number);
        // EIP-4906: tell marketplaces to refresh this token's metadata.
        // If the tuner is orphaned (DEL.tuner has been swapped), this call
        // reverts — which cleanly bricks orphaned setters by design.
        IDEL(del).emitMetadataUpdate(tokenId);
    }

    function _defaultFor(uint256 tokenId, uint8 fieldIdx) internal view returns (int32) {
        uint8 behaviourIdx = IDEL(del).behaviourIdxOf(tokenId);
        bytes memory defaults = IDELDataStore(IDEL(del).dataStore()).behaviourDefaults();
        uint256 off = uint256(behaviourIdx) * FIELD_COUNT * 4 + uint256(fieldIdx) * 4;
        return _readI32(defaults, off);
    }

    /// @dev Big-endian int32 read from a bytes blob. Matches the encoder's
    /// `encodeI32(value)` output (4 bytes, scale-10000 signed).
    function _readI32(bytes memory data, uint256 offset) internal pure returns (int32) {
        uint32 u = (uint32(uint8(data[offset]))     << 24) |
                   (uint32(uint8(data[offset + 1])) << 16) |
                   (uint32(uint8(data[offset + 2])) << 8)  |
                    uint32(uint8(data[offset + 3]));
        return int32(u);
    }
}

interface IDELTuner {
    function isTuned(uint256 tokenId) external view returns (bool);
    function lastTunedBy(uint256 tokenId) external view returns (address);
    function effectiveField(uint256 tokenId, uint8 fieldIdx) external view returns (int32);
    function effectiveFields(uint256 tokenId) external view returns (int32[21] memory);
}
