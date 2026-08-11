// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Linked body-corruption renderer logic for DAEMONS 24x24 type masks.
library DaemonCorruption {
    uint8 private constant SIZE = 24;
    uint8 private constant MIN_CORRUPTION_DELTA = 4;
    uint24 private constant GRID_MASK = 0xFFFFFF;

    function mutate(
        uint24[24] memory rows,
        uint256 seed,
        uint256 objectId,
        bytes32 corruptionState,
        uint64 corruptionEpoch,
        uint8 tier,
        uint8 glitchType,
        bool forceOverdrive
    ) public pure returns (uint24[24] memory out) {
        bytes32 entropy = _entropy(seed, objectId, corruptionState, corruptionEpoch, tier, glitchType);
        uint16 intensityPct = _intensityPct(entropy, forceOverdrive);
        uint8 variant = uint8(uint256(entropy) % 4);
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 row = rows[y];
            if (glitchType == 0) {
                out[y] = _displaceRow(row, entropy, y, corruptionEpoch, variant);
            } else if (glitchType == 1) {
                out[y] = row & _dropMask(entropy, y, _dropoutDensity(variant));
            } else if (glitchType == 2) {
                out[y] = _smearRow(row, entropy, y, corruptionEpoch, variant);
            } else if (glitchType == 3) {
                out[y] = _scanlineRow(row, entropy, y, corruptionEpoch, variant);
            } else if (glitchType == 4) {
                out[y] = _staticRow(row, entropy, y, variant);
            } else if (glitchType == 5) {
                out[y] = _echoRow(rows, row, entropy, y, corruptionEpoch, variant);
            } else {
                out[y] = _polymorphRow(rows, row, entropy, y, corruptionEpoch, variant);
            }
        }
        out = _overdrive(rows, out, entropy, glitchType);
        if (intensityPct == 150) {
            out = _overdrive150(rows, out, entropy, glitchType);
        } else {
            out = _applyIntensity(rows, out, entropy, intensityPct);
        }
        if (_changedPixels(rows, out) < MIN_CORRUPTION_DELTA) {
            out = _applyMinimumCorruption(rows, out, entropy);
        }
    }

    function corruptionIntensityPct(
        uint256 seed,
        uint256 objectId,
        bytes32 corruptionState,
        uint64 corruptionEpoch,
        uint8 tier,
        uint8 glitchType,
        bool forceOverdrive
    ) public pure returns (uint16) {
        return _intensityPct(
            _entropy(seed, objectId, corruptionState, corruptionEpoch, tier, glitchType), forceOverdrive
        );
    }

    function _entropy(
        uint256 seed,
        uint256 objectId,
        bytes32 corruptionState,
        uint64 corruptionEpoch,
        uint8 tier,
        uint8 glitchType
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("TEST_GLITCH_V3", seed, objectId, corruptionState, corruptionEpoch, glitchType, tier)
        );
    }

    function _intensityPct(bytes32 entropy, bool forceOverdrive) private pure returns (uint16) {
        if (forceOverdrive) return 150;
        uint256 roll = uint256(keccak256(abi.encodePacked(entropy, "DAEMON_GLITCH_INTENSITY"))) % 100;
        if (roll < 35) return 20;
        if (roll < 45) return 25;
        if (roll < 55) return 33;
        if (roll < 85) return 50;
        if (roll < 95) return 75;
        if (roll < 99) return 100;
        return 150;
    }

    function _applyIntensity(uint24[24] memory cleanRows, uint24[24] memory targetRows, bytes32 entropy, uint16 pct)
        private
        pure
        returns (uint24[24] memory out)
    {
        if (pct >= 100) return targetRows;
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 diff = cleanRows[y] ^ targetRows[y];
            uint24 row = cleanRows[y];
            for (uint8 x = 0; x < SIZE; ++x) {
                uint24 bit = uint24(1) << x;
                if ((diff & bit) == 0) continue;
                uint8 roll =
                    uint8(uint256(keccak256(abi.encodePacked("DAEMON_GLITCH_INTENSITY_STEP", entropy, y, x))) % 100);
                if (roll < pct) {
                    if ((targetRows[y] & bit) != 0) row |= bit;
                    else row &= GRID_MASK ^ bit;
                }
            }
            out[y] = row;
        }
    }

    function _shift(uint24 row, int8 shift) private pure returns (uint24) {
        if (shift > 0) return uint24((uint256(row) << uint8(shift)) & GRID_MASK);
        if (shift < 0) return uint24(uint256(row) >> uint8(-shift));
        return row;
    }

    function _signedShift(bytes32 entropy, uint8 y) private pure returns (int8) {
        return int8(uint8(uint256(entropy >> (y * 3)) % 3)) - 1;
    }

    function _dropMask(bytes32 entropy, uint8 y, uint8 density) private pure returns (uint24 mask) {
        for (uint8 x = 0; x < SIZE; ++x) {
            uint8 offset = uint8((uint16(x) * 11 + uint16(y) * 17) % 248);
            if (uint8(uint256(entropy >> offset) % density) != 0) mask |= uint24(1) << x;
        }
    }

    function _dropoutDensity(uint8 variant) private pure returns (uint8) {
        if (variant == 0) return 11;
        if (variant == 1) return 13;
        if (variant == 2) return 15;
        return 17;
    }

    function _displaceRow(uint24 row, bytes32 entropy, uint8 y, uint64 corruptionEpoch, uint8 variant)
        private
        pure
        returns (uint24)
    {
        uint8 phase = uint8((uint256(corruptionEpoch) + y + variant) % (5 + variant));
        if (variant == 0) {
            return uint8(uint256(entropy >> ((y + 13) % 32)) % 3) == 0 ? _shift(row, _signedShift(entropy, y)) : row;
        }
        if (variant == 1) return phase == 0 ? _shift(row, _signedShift(entropy, y)) : row;
        if (variant == 2) return phase <= 1 ? _shift(row, _signedShift2(entropy, y)) : row;
        return phase == 0 ? _shift(row, 1) : (phase == 3 ? _shift(row, -1) : row);
    }

    function _smearRow(uint24 row, bytes32 entropy, uint8 y, uint64 corruptionEpoch, uint8 variant)
        private
        pure
        returns (uint24)
    {
        uint8 modulus = 5 + variant;
        uint8 phase = uint8((uint256(corruptionEpoch) + y) % modulus);
        if (variant == 0 && (phase == 0 || phase == 3)) {
            return row | _shift(row, _signedShift(entropy, y) >= 0 ? int8(1) : int8(-1));
        }
        if (variant == 1 && phase <= 1) return row | _shift(row, 1);
        if (variant == 2 && (phase == 0 || phase == 4)) return row | _shift(row, -1);
        if (variant == 3 && (phase == 1 || phase == 5)) return row | _shift(row, _signedShift2(entropy, y));
        if (phase == modulus - 1) return row | _shift(row, 2);
        return row;
    }

    function _scanlineRow(uint24 row, bytes32 entropy, uint8 y, uint64 corruptionEpoch, uint8 variant)
        private
        pure
        returns (uint24)
    {
        uint8 modulus = 4 + variant;
        uint8 phase = uint8((y + uint8(corruptionEpoch)) % modulus);
        if (variant == 0) return phase == 0 ? _shift(row, 1) : (phase == 2 ? _shift(row, -1) : row);
        if (variant == 1) return phase == 0 ? _shift(row, _signedShift(entropy, y)) : row;
        if (variant == 2) return phase <= 1 ? _shift(row, 1) : (phase == 3 ? _shift(row, -1) : row);
        return phase == 0 ? _shift(row, -1) : (phase == 3 ? _shift(row, 1) : row);
    }

    function _staticRow(uint24 row, bytes32 entropy, uint8 y, uint8 variant) private pure returns (uint24) {
        uint8 density = variant == 0 ? 18 : (variant == 1 ? 15 : (variant == 2 ? 22 : 17));
        uint24 mask = variant == 2 ? _dilate(_dilate(row)) : _dilate(row);
        return row ^ (_noise(entropy, y, density) & mask);
    }

    function _echoRow(
        uint24[24] memory rows,
        uint24 row,
        bytes32 entropy,
        uint8 y,
        uint64 corruptionEpoch,
        uint8 variant
    ) private pure returns (uint24) {
        uint8 modulus = 4 + variant;
        uint8 phase = uint8((y + uint8(corruptionEpoch)) % modulus);
        if (phase == 0) return row | _shift(row, variant == 2 ? int8(-2) : int8(2));
        if (phase == 2) {
            uint8 sourceY = (y + 1 + uint8(uint256(entropy >> ((y % 16) * 8)) % (2 + variant))) % SIZE;
            return row | _shift(rows[sourceY], variant == 3 ? _signedShift2(entropy, y) : _signedShift(entropy, y));
        }
        if (variant == 1 && phase == 3) return row | (_shift(row, -1) & _dilate(row));
        return row;
    }

    function _polymorphRow(
        uint24[24] memory rows,
        uint24 row,
        bytes32 entropy,
        uint8 y,
        uint64 corruptionEpoch,
        uint8 variant
    ) private pure returns (uint24) {
        uint24 above = y == 0 ? uint24(0) : rows[y - 1];
        uint24 below = y + 1 == SIZE ? uint24(0) : rows[y + 1];
        uint24 edge = _edge(row);
        uint24 innerEdge = row & _dilate(edge);
        uint24 contour = edge & _dilate(row | above | below);
        uint24 protrusions = contour
            & (_noise(entropy, y + variant, 2) | _shift(_noise(entropy, y + 19 + variant, 3), _signedShift(entropy, y)));
        uint24 lobes = _dilate(protrusions) & _dilate(contour);
        uint24 notches = innerEdge & _noise(entropy, y + 11 + variant, 2 + variant);
        uint24 carve = notches | (_shift(notches, _signedShift(entropy, y)) & innerEdge);
        uint24 neighborBleed = (above | below) & _dilate(edge) & _noise(entropy, y + 29 + variant, 2);
        uint8 phase = uint8((y + uint8(corruptionEpoch) + variant) % 5);

        if (variant == 0) {
            if (phase == 0 || phase == 3) return row | lobes;
            if (phase == 1) return row | _shift(protrusions, _signedShift(entropy, y));
            if (phase == 2) return row & (GRID_MASK ^ carve);
        } else if (variant == 1) {
            if (phase == 0) return row | _shift(lobes, _signedShift(entropy, y));
            if (phase == 1 || phase == 3) {
                return row | (_shift(row, _signedShift(entropy, y)) & _dilate(contour)) | neighborBleed;
            }
            if (phase == 2) return row & (GRID_MASK ^ (carve & _dropMask(entropy, y, 2)));
        } else if (variant == 2) {
            if (phase == 0 || phase == 4) return row | _shift(lobes, _signedShift2(entropy, y));
            if (phase == 1) return row & (GRID_MASK ^ carve);
            if (phase == 2) return row | neighborBleed;
            if (phase == 3) return row ^ ((carve | lobes) & _dilate(row));
        } else {
            if (phase == 0) return row | (lobes & _dropMask(entropy, y, 2));
            if (phase == 1) return row | _shift(lobes, 1);
            if (phase == 2) return row | neighborBleed;
            if (phase == 3) return row | _shift(lobes, -1);
            if (phase == 4) return (row | protrusions) & (GRID_MASK ^ (carve & _dropMask(entropy, y, 2)));
        }
        return row;
    }

    function _signedShift2(bytes32 entropy, uint8 y) private pure returns (int8) {
        return int8(uint8(uint256(entropy >> ((y * 5) % 248)) % 5)) - 2;
    }

    function _noise(bytes32 entropy, uint8 y, uint8 density) private pure returns (uint24 row) {
        for (uint8 x = 0; x < SIZE; ++x) {
            if (uint8(uint256(entropy >> ((x * 5 + y) % 32)) % density) == 0) row |= uint24(1) << x;
        }
    }

    function _overdrive(uint24[24] memory cleanRows, uint24[24] memory baseRows, bytes32 entropy, uint8 glitchType)
        private
        pure
        returns (uint24[24] memory out)
    {
        out = baseRows;
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 row = cleanRows[y];
            if (glitchType == 1) out[y] &= _dropMask(entropy, y, 3);
            if (glitchType == 2 && y % 4 == 1) out[y] |= _shift(row, 3);
            if (glitchType == 2 && y % 5 == 2) out[y] |= _shift(row, -3);
            if (glitchType == 5 && y % 2 == 1) out[y] |= _shift(cleanRows[(y + 2) % SIZE], 3);
            if (glitchType == 5 && y % 4 == 2) out[y] |= _shift(cleanRows[(y + SIZE - 2) % SIZE], -3);
            if (y % 2 == 0) out[y] |= _shift(row, 2);
            if (y % 3 == 0) out[y] |= _shift(row, -2);
            out[y] ^= _noise(entropy, y, 6) & _dilate(_dilate(row));
        }
    }

    function _overdrive150(uint24[24] memory cleanRows, uint24[24] memory baseRows, bytes32 entropy, uint8 glitchType)
        private
        pure
        returns (uint24[24] memory out)
    {
        bytes32 boostEntropy = keccak256(abi.encodePacked(entropy, "TEST_GLITCH_OVERDRIVE_V3"));
        out = baseRows;
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 row = cleanRows[y];
            if (glitchType == 1) out[y] &= _dropMask(boostEntropy, y, 2);
            if (y % 2 == 0) out[y] |= _shift(row, 3);
            if (y % 3 == 0) out[y] |= _shift(row, -3);
            if (y % 4 == 0) out[y] |= _shift(row, _signedShift2(boostEntropy, y));
            out[y] ^= _noise(boostEntropy, y, 4) & _dilate(_dilate(_dilate(row)));
        }
    }

    function _dilate(uint24 row) private pure returns (uint24) {
        return row | _shift(row, 1) | _shift(row, -1);
    }

    function _edge(uint24 row) private pure returns (uint24) {
        return _dilate(row) & (GRID_MASK ^ row);
    }

    function _changedPixels(uint24[24] memory cleanRows, uint24[24] memory mutatedRows)
        private
        pure
        returns (uint16 count)
    {
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 diff = cleanRows[y] ^ mutatedRows[y];
            for (uint8 x = 0; x < SIZE; ++x) {
                if ((diff & (uint24(1) << x)) != 0) count++;
            }
        }
    }

    function _applyMinimumCorruption(uint24[24] memory cleanRows, uint24[24] memory mutatedRows, bytes32 entropy)
        private
        pure
        returns (uint24[24] memory out)
    {
        out = mutatedRows;
        uint16 changed = _changedPixels(cleanRows, out);

        for (uint8 attempt = 0; changed < MIN_CORRUPTION_DELTA && attempt < 72; ++attempt) {
            uint8 y = uint8(uint256(entropy >> ((attempt % 32) * 8)) + uint256(attempt) * 7) % SIZE;
            uint8 startX = uint8(uint256(entropy >> (((attempt + 11) % 32) * 8)) + attempt) % SIZE;
            uint24 cleanRow = cleanRows[y];
            for (uint8 step = 0; step < SIZE && changed < MIN_CORRUPTION_DELTA; ++step) {
                uint8 x = (startX + step) % SIZE;
                uint24 bit = uint24(1) << x;
                if ((cleanRow & bit) != 0 && (out[y] & bit) != 0) {
                    out[y] &= GRID_MASK ^ bit;
                    changed++;
                    break;
                }
            }
        }

        for (uint8 attempt = 0; changed < MIN_CORRUPTION_DELTA && attempt < 72; ++attempt) {
            uint8 y = uint8(uint256(entropy >> (((attempt + 17) % 32) * 8)) + uint256(attempt) * 5) % SIZE;
            uint8 startX = uint8(uint256(entropy >> (((attempt + 23) % 32) * 8)) + attempt) % SIZE;
            uint24 candidates = _dilate(cleanRows[y]) & (GRID_MASK ^ cleanRows[y]);
            for (uint8 step = 0; step < SIZE && changed < MIN_CORRUPTION_DELTA; ++step) {
                uint8 x = (startX + step) % SIZE;
                uint24 bit = uint24(1) << x;
                if ((candidates & bit) != 0 && (out[y] & bit) == 0) {
                    out[y] |= bit;
                    changed++;
                    break;
                }
            }
        }
    }
}
