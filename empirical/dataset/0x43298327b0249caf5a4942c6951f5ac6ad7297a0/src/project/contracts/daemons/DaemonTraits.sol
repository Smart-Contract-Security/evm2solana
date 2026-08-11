// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DaemonArtData} from "./DaemonArtData.sol";

struct DaemonTraitSet {
    uint8 background;
    uint8 daemonType;
    uint8 eyes;
    uint8 mouth;
    uint8 glitchType;
    uint8 facePalette;
    uint8 mouthPalette;
    uint8 shadowPalette;
    uint8 accessory;
    uint8 flags;
}

struct DaemonTraitRolls {
    uint8 background;
    uint8 flags;
    bool laserEyes;
    bool ghostyMouth;
    uint256 accessorySerial;
    uint256 traitSerial;
}

library DaemonTraits {
    uint8 internal constant FLAG_MONO = 1 << 0;
    uint8 internal constant FLAG_ACCESSORY = 1 << 1;
    uint8 internal constant FLAG_NO_MOUTH = 1 << 3;
    uint8 internal constant FLAG_BODY_INVERTED = 1 << 4;
    uint8 internal constant FLAG_REFLECTED = 1 << 5;
    uint8 internal constant SCHIZO_EYES_ID = 14;
    uint8 internal constant REGULAR_LASER_EYES_ID = 15;
    uint8 internal constant RGBCMY_LASER_EYES_ID = 16;
    uint8 internal constant MONO_LASER_EYES_ID = 12;
    uint8 internal constant REGULAR_VISOR_EYES_ID = 18;
    uint8 internal constant MONO_VISOR_EYES_ID = 15;
    uint8 internal constant GHOSTY_MOUTH_ID = 3;
    uint8 internal constant GRIN_MOUTH_ID = 27;
    uint8 internal constant FIXED_COLOR_3D_EYES_ID = 19;
    uint8 internal constant BLACK_BACKGROUND_ID = 0;
    uint8 internal constant MED_BACKGROUND_ID = 2;
    uint8 internal constant JPEG_TYPE_ID = 1;
    uint8 internal constant SHIKIGAMI_TYPE_ID = 6;
    uint8 internal constant ET_TYPE_ID = 8;
    uint8 internal constant STUX_TYPE_ID = 29;
    uint8 internal constant HALO_ACCESSORY_ID = 0;
    uint8 internal constant QUESTION_ACCESSORY_ID = 2;
    uint8 internal constant FOUR_O_FOUR_ACCESSORY_ID = 8;
    uint8 internal constant SQUIGGLE_ACCESSORY_ID = 10;
    uint8 internal constant FLAME_ACCESSORY_ID = 11;
    uint8 internal constant WATER_ACCESSORY_ID = 12;
    uint8 internal constant NORMAL_ACCESSORY_WEIGHT_TOTAL = 47;
    bytes32 internal constant NORMAL_ACCESSORY_SLOTS_A =
        hex"000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f";
    bytes15 internal constant NORMAL_ACCESSORY_SLOTS_B = hex"000102030405060708090b0c0d0e0f";
    uint8 internal constant BODY_BLOCKED_FALLBACK_ACCESSORY_COUNT = 13;
    bytes13 internal constant BODY_BLOCKED_FALLBACK_ACCESSORY_SLOTS = hex"01020304050607090b0c0d0e0f";
    uint8 internal constant STUX_FALLBACK_ACCESSORY_COUNT = 12;
    bytes12 internal constant STUX_FALLBACK_ACCESSORY_SLOTS = hex"010304050607090b0c0d0e0f";
    uint8 internal constant WHITE_AURA_PALETTE_ID = DaemonArtData.PALETTE_COUNT;
    uint8 internal constant RGBCMY_PALETTE_ID = DaemonArtData.PALETTE_COUNT + 1;
    uint8 internal constant BLACK_PALETTE_ID = DaemonArtData.PALETTE_COUNT + 2;
    uint8 internal constant AURA_OPTION_COUNT = 10;
    uint8 internal constant AURA_SOLID_COLOR_COUNT = DaemonArtData.PALETTE_COUNT + 1;
    uint8 internal constant AURA_EXTRA_SOLID_START_SLOT = 7;
    uint8 internal constant AURA_RGBCMY_SLOT = 9;
    uint8 internal constant NORMAL_FACE_PALETTE_OPTION_COUNT = DaemonArtData.PALETTE_COUNT;
    uint8 internal constant WHITE_BODY_FACE_BLACK_OPTION_COUNT = DaemonArtData.PALETTE_COUNT + 1;
    uint8 internal constant RGBCMY_EYE_ROLL_SLOTS = 10;
    uint8 internal constant RGBCMY_LASER_ROLL_SLOTS = 50;
    uint8 internal constant RGBCMY_MOUTH_ROLL_SLOTS = 3;
    bytes32 internal constant RGBCMY_EYES_SALT = hex"1bd26d5d7e875122c19c77b1ca7f0256e0ea0e692bcc7439639cbcb31593c77b";
    bytes32 internal constant RGBCMY_MOUTH_SALT = hex"8464073ee9b363bfcef6f1a2b95d47f91ec0af1789578f4863bdb7690ac0c1dd";
    uint16 internal constant EYE_WEIGHT_TOTAL = 100;
    uint16 internal constant MOUTH_WEIGHT_TOTAL = 100;
    uint16 internal constant TYPE_WEIGHT_TOTAL = 10_000;
    uint16 internal constant TYPE_COMMON_TOTAL = 6_000;
    uint16 internal constant TYPE_UNCOMMON_TOTAL = 2_350;
    uint16 internal constant TYPE_RARE_TOTAL = 950;
    uint16 internal constant TYPE_ULTRA_TOTAL = 500;
    uint16 internal constant TYPE_JPEG_TOTAL = 125;
    uint16 internal constant TYPE_ET_TOTAL = 75;
    uint8 internal constant TYPE_COMMON_COUNT = 15;
    uint8 internal constant TYPE_UNCOMMON_COUNT = 12;
    uint8 internal constant TYPE_RARE_COUNT = 8;
    uint8 internal constant TYPE_ULTRA_COUNT = 3;
    bytes15 internal constant TYPE_COMMON_IDS = hex"1213141516181e1f20212223242527";
    bytes12 internal constant TYPE_UNCOMMON_IDS = hex"090a0b0c0d0e0f1011171a1c";
    bytes8 internal constant TYPE_RARE_IDS = hex"000203040506071d";
    bytes3 internal constant TYPE_ULTRA_IDS = hex"191b26";

    function pack(DaemonTraitSet memory traits) internal pure returns (uint256 word) {
        word |= uint256(traits.background);
        word |= uint256(traits.daemonType) << 8;
        word |= uint256(traits.eyes) << 16;
        word |= uint256(traits.mouth) << 24;
        word |= uint256(traits.glitchType) << 32;
        word |= uint256(traits.facePalette) << 40;
        word |= uint256(traits.mouthPalette) << 48;
        word |= uint256(traits.shadowPalette) << 56;
        word |= uint256(traits.accessory) << 64;
        word |= uint256(traits.flags) << 72;
    }

    function unpack(uint256 word) internal pure returns (DaemonTraitSet memory traits) {
        traits.background = uint8(word);
        traits.daemonType = uint8(word >> 8);
        traits.eyes = uint8(word >> 16);
        traits.mouth = uint8(word >> 24);
        traits.glitchType = uint8(word >> 32);
        traits.facePalette = uint8(word >> 40);
        traits.mouthPalette = uint8(word >> 48);
        traits.shadowPalette = uint8(word >> 56);
        traits.accessory = uint8(word >> 64);
        traits.flags = uint8(word >> 72);
    }

    function derive(uint256 seed, uint256 objectId) public pure returns (uint256) {
        DaemonTraitRolls memory rolls = _deriveRolls(seed, objectId);
        bool mono = (rolls.flags & FLAG_MONO) != 0;
        bool noMouth = (rolls.flags & FLAG_NO_MOUTH) != 0;
        bool bodyInverted = (rolls.flags & FLAG_BODY_INVERTED) != 0;
        DaemonTraitSet memory traits;
        bool hasNormalAccessory = (rolls.flags & FLAG_ACCESSORY) != 0;
        if (hasNormalAccessory) {
            traits.accessory = _normalAccessorySlot(_permute(rolls.accessorySerial, NORMAL_ACCESSORY_WEIGHT_TOTAL));
        }
        bool squiggleAccessory = hasNormalAccessory && traits.accessory == SQUIGGLE_ACCESSORY_ID;
        bool squiggleBlockedAccessory;
        uint256 auraPaletteCount = AURA_OPTION_COUNT;
        uint256 eyeWeightTotal = _eyeWeightTotal(mono, bodyInverted);
        uint256 modulus = bodyInverted
            ? _whiteBodyTraitModulus(rolls.laserEyes, noMouth, eyeWeightTotal, auraPaletteCount)
            : _standardTraitModulus(mono, noMouth, eyeWeightTotal, auraPaletteCount);
        uint256 typeAndValue = _weightedTypeAndValue(rolls.traitSerial, modulus);

        traits.background = rolls.background;
        traits.daemonType = uint8(typeAndValue);
        if (traits.daemonType == ET_TYPE_ID && bodyInverted) {
            uint256 normalModulus = _standardTraitModulus(mono, noMouth, eyeWeightTotal, auraPaletteCount);
            uint256 valueWithInversion = typeAndValue >> 8;
            uint256 typeSerial = valueWithInversion / modulus;
            uint256 remainder = valueWithInversion % modulus;
            typeAndValue = uint256(traits.daemonType) | ((typeSerial * normalModulus + remainder % normalModulus) << 8);
            rolls.flags &= ~FLAG_BODY_INVERTED;
            bodyInverted = false;
            modulus = normalModulus;
        }
        bool shikigamiBlackBackground =
            traits.daemonType == SHIKIGAMI_TYPE_ID && traits.background == BLACK_BACKGROUND_ID;
        bool etMedBackground = traits.daemonType == ET_TYPE_ID && traits.background == MED_BACKGROUND_ID;
        if (shikigamiBlackBackground) traits.background = _shikigamiFallbackBackground(objectId);
        if (etMedBackground) traits.background = _etFallbackBackground(objectId);
        if (hasNormalAccessory) {
            traits.accessory = _compatibleAccessory(traits.accessory, traits.daemonType, rolls.accessorySerial);
            if (squiggleAccessory && traits.accessory != SQUIGGLE_ACCESSORY_ID) {
                squiggleAccessory = false;
                squiggleBlockedAccessory = true;
            }
            if (
                !squiggleAccessory && !_isSquiggleBlockedType(traits.daemonType)
                    && _rgbcmyRollSlot(seed, objectId, keccak256("TEST_SQUIGGLE_TUNE_V3")) == 0
            ) {
                traits.accessory = SQUIGGLE_ACCESSORY_ID;
                squiggleAccessory = true;
                squiggleBlockedAccessory = false;
            }
        }
        uint256 value = typeAndValue >> 8;
        uint8 laserEyeId = mono ? MONO_LASER_EYES_ID : REGULAR_LASER_EYES_ID;
        if (bodyInverted) {
            if (rolls.laserEyes) {
                traits.eyes = laserEyeId;
                traits.facePalette = uint8(value % NORMAL_FACE_PALETTE_OPTION_COUNT);
                value /= NORMAL_FACE_PALETTE_OPTION_COUNT;
            } else {
                traits.eyes = _weightedEyeId(value % eyeWeightTotal, mono, true);
                value /= eyeWeightTotal;
                traits.facePalette = _whiteBodyFacePaletteId(uint8(value % WHITE_BODY_FACE_BLACK_OPTION_COUNT));
                if (_isWhiteBodyBlackEyeEligible(traits.eyes, mono)) {
                    if (_rgbcmyRollSlot(seed, objectId, keccak256("TEST_WHITE_BODY_BLACK_EYES_V3")) < 20) {
                        traits.facePalette = BLACK_PALETTE_ID;
                    }
                } else if (traits.facePalette == BLACK_PALETTE_ID) {
                    traits.facePalette = 0;
                }
                value /= WHITE_BODY_FACE_BLACK_OPTION_COUNT;
            }

            if (!noMouth) {
                traits.mouth = rolls.ghostyMouth ? GHOSTY_MOUTH_ID : _weightedMouthId(value % MOUTH_WEIGHT_TOTAL);
                value /= MOUTH_WEIGHT_TOTAL;
                traits.mouthPalette = _whiteBodyFacePaletteId(uint8(value % WHITE_BODY_FACE_BLACK_OPTION_COUNT));
                value /= WHITE_BODY_FACE_BLACK_OPTION_COUNT;
            }

            traits.glitchType = uint8(value % DaemonArtData.GLITCH_TYPE_COUNT);
            value /= DaemonArtData.GLITCH_TYPE_COUNT;
        } else {
            if (rolls.laserEyes) {
                traits.eyes = laserEyeId;
            } else if (mono) {
                traits.eyes = _weightedEyeId(value % eyeWeightTotal, true, false);
            } else {
                traits.eyes = _weightedEyeId(value % eyeWeightTotal, false, false);
            }
            value /= eyeWeightTotal;
            if (!noMouth) {
                traits.mouth = rolls.ghostyMouth ? GHOSTY_MOUTH_ID : _weightedMouthId(value % MOUTH_WEIGHT_TOTAL);
                value /= MOUTH_WEIGHT_TOTAL;
            }
            traits.glitchType = uint8(value % DaemonArtData.GLITCH_TYPE_COUNT);
            value /= DaemonArtData.GLITCH_TYPE_COUNT;
            if (!mono) {
                (traits.facePalette, traits.mouthPalette, value) = _deriveFacePalettes(value, noMouth);
            }
        }
        uint8 auraOption = squiggleBlockedAccessory
            ? uint8(_permute(rolls.accessorySerial + objectId, AURA_OPTION_COUNT))
            : uint8(value % auraPaletteCount);
        value /= auraPaletteCount;
        traits.shadowPalette = _auraPaletteId(auraOption, objectId, bodyInverted);
        if (!mono && _isRGBCMYEyeEligible(traits.eyes)) {
            uint8 rgbcmyEyeRollSlots =
                traits.eyes == REGULAR_LASER_EYES_ID ? RGBCMY_LASER_ROLL_SLOTS : RGBCMY_EYE_ROLL_SLOTS;
            if (
                _rgbcmyRollSlot(seed, objectId, RGBCMY_EYES_SALT) < rgbcmyEyeRollSlots
                    && !(traits.eyes == REGULAR_LASER_EYES_ID && _isRGBCMYLaserBlockedType(traits.daemonType))
            ) {
                if (traits.eyes == REGULAR_LASER_EYES_ID) traits.eyes = RGBCMY_LASER_EYES_ID;
                traits.facePalette = RGBCMY_PALETTE_ID;
            }
        }
        if (
            !mono && !noMouth && _rgbcmyRollSlot(seed, objectId, RGBCMY_MOUTH_SALT) < RGBCMY_MOUTH_ROLL_SLOTS
                && _isRGBCMYMouthEligible(traits.mouth)
        ) {
            traits.mouthPalette = RGBCMY_PALETTE_ID;
        }
        if (!mono && traits.eyes == FIXED_COLOR_3D_EYES_ID) {
            traits.facePalette = 0;
        }
        if (shikigamiBlackBackground || etMedBackground) {
            traits.glitchType = uint8(
                (uint256(traits.glitchType)
                        + 1
                        + _permute(objectId + uint256(traits.daemonType), DaemonArtData.GLITCH_TYPE_COUNT - 1))
                    % DaemonArtData.GLITCH_TYPE_COUNT
            );
        }
        traits.flags = rolls.flags;
        return pack(traits);
    }

    function _deriveRolls(uint256 seed, uint256 objectId) private pure returns (DaemonTraitRolls memory rolls) {
        uint256 index = _traitScheduleIndex(seed, objectId);
        uint256 serial;
        (rolls.background, serial) = _weightedBackgroundSerial(index);
        (bool mono, uint256 monoSerial) = _weightedFlagSerial(serial, 8, 5);
        if (mono) rolls.flags |= FLAG_MONO;
        (bool accessory, uint256 accessorySerial) = _weightedFlagSerial(monoSerial, 20, 17);
        rolls.accessorySerial = accessorySerial;
        if (accessory) rolls.flags |= FLAG_ACCESSORY;
        uint256 eyesSerial;
        (rolls.laserEyes, eyesSerial) = _weightedFlagSerial(accessorySerial, 2, 43);
        (bool noMouth, uint256 mouthPresenceSerial) = _weightedFlagSerial(eyesSerial, 2, 61);
        if (noMouth) rolls.flags |= FLAG_NO_MOUTH;

        uint256 mouthSerial = mouthPresenceSerial;
        if (!noMouth) {
            (rolls.ghostyMouth, mouthSerial) = _weightedFlagSerial(mouthPresenceSerial, 8, 71);
        }
        uint256 renderStateSerial = mouthSerial * 997 + 89;
        (bool bodyInverted, uint256 bodySerial) = _weightedFlagSerialOutOf(renderStateSerial, 42, 1000, 97);
        if (bodyInverted) rolls.flags |= FLAG_BODY_INVERTED;
        rolls.traitSerial = bodySerial;
        (bool reflected,) = _weightedFlagSerial(bodySerial, 1, 131);
        if (reflected) rolls.flags |= FLAG_REFLECTED;
    }

    function fingerprint(uint256 word) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(canonicalFingerprintWord(word)));
    }

    function canonicalFingerprintWord(uint256 word) internal pure returns (uint256) {
        DaemonTraitSet memory traits = unpack(word);
        traits.flags &= FLAG_MONO | FLAG_ACCESSORY | FLAG_NO_MOUTH | FLAG_BODY_INVERTED | FLAG_REFLECTED;
        if ((traits.flags & FLAG_ACCESSORY) == 0) traits.accessory = 0;
        if ((traits.flags & FLAG_NO_MOUTH) != 0) {
            traits.mouth = 0;
            traits.mouthPalette = 0;
        }
        if ((traits.flags & FLAG_MONO) == 0 && traits.eyes == FIXED_COLOR_3D_EYES_ID) {
            traits.facePalette = 0;
        }
        bool mono = (traits.flags & FLAG_MONO) != 0;
        bool invertedBody = (traits.flags & FLAG_BODY_INVERTED) != 0;
        if (mono && !invertedBody) {
            traits.facePalette = 0;
            traits.mouthPalette = 0;
        }
        return pack(traits);
    }

    function isMono(uint256 word) internal pure returns (bool) {
        return (uint8(word >> 72) & FLAG_MONO) != 0;
    }

    function hasAccessory(uint256 word) internal pure returns (bool) {
        return (uint8(word >> 72) & FLAG_ACCESSORY) != 0;
    }

    function isCorruptionOverdrive(uint256) internal pure returns (bool) {
        return false;
    }

    function hasMouth(uint256 word) internal pure returns (bool) {
        return (uint8(word >> 72) & FLAG_NO_MOUTH) == 0;
    }

    function hasInvertedBody(uint256 word) internal pure returns (bool) {
        return (uint8(word >> 72) & FLAG_BODY_INVERTED) != 0;
    }

    function isReflected(uint256 word) internal pure returns (bool) {
        return (uint8(word >> 72) & FLAG_REFLECTED) != 0;
    }

    function _weightedBackgroundSerial(uint256 index) private pure returns (uint8 background, uint256 serial) {
        uint256 cycle = index / 100;
        uint256 slot = index % 100;
        if (slot < 2) return (0, cycle * 2 + slot);
        if (slot < 51) return (1, cycle * 49 + slot - 2);
        if (slot < 98) return (2, cycle * 47 + slot - 51);
        return (3, cycle * 2 + slot - 98);
    }

    function _normalAccessorySlot(uint256 index) private pure returns (uint8) {
        if (index < 32) return uint8(NORMAL_ACCESSORY_SLOTS_A[index]);
        return uint8(NORMAL_ACCESSORY_SLOTS_B[index - 32]);
    }

    function _shikigamiFallbackBackground(uint256 objectId) private pure returns (uint8) {
        return 1 + uint8(_permute(objectId, DaemonArtData.BACKGROUND_COUNT - 1));
    }

    function _etFallbackBackground(uint256 objectId) private pure returns (uint8) {
        uint256 slot = _permute(objectId, DaemonArtData.BACKGROUND_COUNT - 1);
        if (slot == 0) return BLACK_BACKGROUND_ID;
        if (slot == 1) return 1;
        return 3;
    }

    function _weightedFlagSerial(uint256 index, uint256 trueSlots, uint256 offset)
        private
        pure
        returns (bool selected, uint256 serial)
    {
        return _weightedFlagSerialOutOf(index, trueSlots, 100, offset);
    }

    function _weightedFlagSerialOutOf(uint256 index, uint256 trueSlots, uint256 modulus, uint256 offset)
        private
        pure
        returns (bool selected, uint256 serial)
    {
        uint256 cycle = index / modulus;
        uint256 slot = ((index % modulus) * 997 + offset) % modulus;
        if (slot < trueSlots) return (true, cycle * trueSlots + slot);
        return (false, cycle * (modulus - trueSlots) + slot - trueSlots);
    }

    function _weightedTypeSerial(uint256 index) private pure returns (uint8 daemonType, uint256 serial) {
        uint256 cycle = index / TYPE_WEIGHT_TOTAL;
        uint256 slot = index % TYPE_WEIGHT_TOTAL;
        if (slot < TYPE_COMMON_TOTAL) {
            uint256 commonIndex = (slot * TYPE_COMMON_COUNT) / TYPE_COMMON_TOTAL;
            daemonType = uint8(TYPE_COMMON_IDS[commonIndex]);
            return (daemonType, _serialWithinTypeBucket(slot, TYPE_COMMON_TOTAL, TYPE_COMMON_COUNT, commonIndex, cycle));
        }
        slot -= TYPE_COMMON_TOTAL;
        if (slot < TYPE_UNCOMMON_TOTAL) {
            uint256 uncommonIndex = (slot * TYPE_UNCOMMON_COUNT) / TYPE_UNCOMMON_TOTAL;
            daemonType = uint8(TYPE_UNCOMMON_IDS[uncommonIndex]);
            return
                (
                    daemonType,
                    _serialWithinTypeBucket(slot, TYPE_UNCOMMON_TOTAL, TYPE_UNCOMMON_COUNT, uncommonIndex, cycle)
                );
        }
        slot -= TYPE_UNCOMMON_TOTAL;
        if (slot < TYPE_RARE_TOTAL) {
            uint256 rareIndex = (slot * TYPE_RARE_COUNT) / TYPE_RARE_TOTAL;
            daemonType = uint8(TYPE_RARE_IDS[rareIndex]);
            return (daemonType, _serialWithinTypeBucket(slot, TYPE_RARE_TOTAL, TYPE_RARE_COUNT, rareIndex, cycle));
        }
        slot -= TYPE_RARE_TOTAL;
        uint256 ultraIndex = (slot * TYPE_ULTRA_COUNT) / TYPE_ULTRA_TOTAL;
        if (slot < TYPE_ULTRA_TOTAL) {
            daemonType = uint8(TYPE_ULTRA_IDS[ultraIndex]);
            return (daemonType, _serialWithinTypeBucket(slot, TYPE_ULTRA_TOTAL, TYPE_ULTRA_COUNT, ultraIndex, cycle));
        }
        slot -= TYPE_ULTRA_TOTAL;
        if (slot < TYPE_JPEG_TOTAL) return (JPEG_TYPE_ID, cycle * TYPE_JPEG_TOTAL + slot);
        slot -= TYPE_JPEG_TOTAL;
        return (ET_TYPE_ID, cycle * TYPE_ET_TOTAL + slot);
    }

    function _serialWithinTypeBucket(
        uint256 slot,
        uint256 bucketSize,
        uint256 bucketCount,
        uint256 typeIndex,
        uint256 cycle
    ) private pure returns (uint256) {
        uint256 start = (typeIndex * bucketSize) / bucketCount;
        uint256 end = ((typeIndex + 1) * bucketSize) / bucketCount;
        return cycle * (end - start) + (slot - start);
    }

    function _weightedTypeAndValue(uint256 traitSerial, uint256 modulus) private pure returns (uint256) {
        (uint8 daemonType, uint256 typeSerial) = _weightedTypeSerial(_permute(traitSerial, TYPE_WEIGHT_TOTAL));
        return uint256(daemonType) | (_permute(typeSerial, modulus) << 8);
    }

    function _eyeWeightTotal(bool mono, bool bodyInverted) private pure returns (uint16) {
        mono;
        bodyInverted;
        return EYE_WEIGHT_TOTAL;
    }

    function _weightedEyeId(uint256 slot, bool mono, bool bodyInverted) private pure returns (uint8) {
        if (mono) {
            if (slot < (bodyInverted ? 21 : 17)) return 0;
            slot -= bodyInverted ? 21 : 17;
            if (slot < 7) return 1;
            slot -= 7;
            if (slot < 4) return 2;
            slot -= 4;
            if (slot < 7) return 3;
            slot -= 7;
            if (slot < 7) return 4;
            slot -= 7;
            if (slot < 7) return 5;
            slot -= 7;
            if (slot < 4) return 6;
            slot -= 4;
            if (slot < 7) return 7;
            slot -= 7;
            if (slot < 4) return 8;
            slot -= 4;
            if (slot < 7) return 9;
            slot -= 7;
            if (slot < 7) return 10;
            slot -= 7;
            if (slot < 7) return 11;
            slot -= 7;
            if (slot < 7) return 13;
            slot -= 7;
            if (slot < 4) return 14;
            return bodyInverted ? uint8(14) : uint8(15);
        }
        if (slot < (bodyInverted ? 21 : 18)) return 0;
        slot -= bodyInverted ? 21 : 18;
        if (slot < 7) return 1;
        slot -= 7;
        if (slot < 3) return 2;
        slot -= 3;
        if (slot < 7) return 3;
        slot -= 7;
        if (slot < 7) return 5;
        slot -= 7;
        if (slot < 7) return 6;
        slot -= 7;
        if (slot < 3) return 7;
        slot -= 3;
        if (slot < 7) return 8;
        slot -= 7;
        if (slot < 3) return 9;
        slot -= 3;
        if (slot < 7) return 10;
        slot -= 7;
        if (slot < 7) return 11;
        slot -= 7;
        if (slot < 7) return 12;
        slot -= 7;
        if (slot < 3) return 13;
        slot -= 3;
        if (slot < 3) return SCHIZO_EYES_ID;
        slot -= 3;
        if (slot < 7) return 17;
        slot -= 7;
        if (!bodyInverted) {
            if (slot < 3) return REGULAR_VISOR_EYES_ID;
            slot -= 3;
        }
        return FIXED_COLOR_3D_EYES_ID;
    }

    function _weightedMouthId(uint256 slot) private pure returns (uint8) {
        if (slot < 21) return 0;
        if (slot < 34) return 1;
        if (slot < 38) return 2;
        if (slot < 41) return 4;
        if (slot < 48) return 5;
        if (slot < 53) return 6;
        if (slot < 57) return 7;
        if (slot < 61) return 8;
        if (slot < 63) return 9;
        if (slot < 65) return 10;
        if (slot < 68) return 11;
        if (slot < 70) return 12;
        if (slot < 72) return 13;
        if (slot < 74) return 14;
        if (slot < 76) return 15;
        if (slot < 78) return 16;
        if (slot < 80) return 17;
        if (slot < 82) return 18;
        if (slot < 84) return 19;
        if (slot < 86) return 20;
        if (slot < 88) return 21;
        if (slot < 90) return 22;
        if (slot < 92) return 23;
        if (slot < 93) return 24;
        if (slot < 94) return 25;
        if (slot < 95) return 26;
        if (slot < 97) return 27;
        return 28;
    }

    function _standardTraitModulus(bool mono, bool noMouth, uint256 eyeWeightTotal, uint256 auraPaletteCount)
        private
        pure
        returns (uint256 modulus)
    {
        modulus = eyeWeightTotal * DaemonArtData.GLITCH_TYPE_COUNT;
        if (!noMouth) modulus *= MOUTH_WEIGHT_TOTAL;
        modulus *= _facePaletteModulus(mono, noMouth);
        modulus *= auraPaletteCount;
    }

    function _whiteBodyTraitModulus(bool laserEyes, bool noMouth, uint256 eyeWeightTotal, uint256 auraPaletteCount)
        private
        pure
        returns (uint256 modulus)
    {
        modulus = laserEyes ? NORMAL_FACE_PALETTE_OPTION_COUNT : eyeWeightTotal * WHITE_BODY_FACE_BLACK_OPTION_COUNT;
        if (!noMouth) modulus *= MOUTH_WEIGHT_TOTAL * WHITE_BODY_FACE_BLACK_OPTION_COUNT;
        modulus *= DaemonArtData.GLITCH_TYPE_COUNT * auraPaletteCount;
    }

    function _facePaletteModulus(bool mono, bool noMouth) private pure returns (uint256) {
        if (mono) return 1;
        return noMouth
            ? NORMAL_FACE_PALETTE_OPTION_COUNT
            : NORMAL_FACE_PALETTE_OPTION_COUNT * NORMAL_FACE_PALETTE_OPTION_COUNT;
    }

    function _deriveFacePalettes(uint256 value, bool noMouth)
        private
        pure
        returns (uint8 facePalette, uint8 mouthPalette, uint256 nextValue)
    {
        facePalette = uint8(value % NORMAL_FACE_PALETTE_OPTION_COUNT);
        value /= NORMAL_FACE_PALETTE_OPTION_COUNT;
        if (!noMouth) {
            mouthPalette = uint8(value % NORMAL_FACE_PALETTE_OPTION_COUNT);
            value /= NORMAL_FACE_PALETTE_OPTION_COUNT;
        }
        return (facePalette, mouthPalette, value);
    }

    function _whiteBodyFacePaletteId(uint8 option) private pure returns (uint8) {
        if (option < DaemonArtData.PALETTE_COUNT) return option;
        return BLACK_PALETTE_ID;
    }

    function _isWhiteBodyBlackEyeEligible(uint8 eyeId, bool mono) private pure returns (bool) {
        if (eyeId == 2) return true;
        return mono ? eyeId == 13 || eyeId == 14 : eyeId == 13 || eyeId == 17;
    }

    function _auraPaletteId(uint8 option, uint256 objectId, bool bodyInverted) private pure returns (uint8) {
        if (option == AURA_RGBCMY_SLOT) return RGBCMY_PALETTE_ID;
        uint8 solidPalette = option < AURA_EXTRA_SOLID_START_SLOT
            ? option
            : uint8((objectId + uint256(option)) % AURA_SOLID_COLOR_COUNT);
        if (solidPalette == DaemonArtData.PALETTE_COUNT) {
            return bodyInverted ? BLACK_PALETTE_ID : WHITE_AURA_PALETTE_ID;
        }
        return solidPalette;
    }

    function _isRGBCMYEyeEligible(uint8 eyeId) private pure returns (bool) {
        return eyeId == 0 || eyeId == 1 || eyeId == 5 || eyeId == 6 || eyeId == 9 || eyeId == REGULAR_LASER_EYES_ID;
    }

    function _isRGBCMYMouthEligible(uint8 mouthId) private pure returns (bool) {
        return mouthId == 0 || mouthId == 1 || mouthId == GRIN_MOUTH_ID;
    }

    function _isRGBCMYLaserBlockedType(uint8 typeId) private pure returns (bool) {
        return typeId == STUX_TYPE_ID;
    }

    function _isHaloBlockedType(uint8 typeId) private pure returns (bool) {
        return typeId == 21 || typeId == 33;
    }

    function _isBodyBlockedAccessory(uint8 accessory) private pure returns (bool) {
        return accessory == HALO_ACCESSORY_ID || accessory == FOUR_O_FOUR_ACCESSORY_ID;
    }

    function _isSquiggleBlockedType(uint8 typeId) private pure returns (bool) {
        return typeId == 3 || typeId == 5 || typeId == 7 || typeId == 14 || typeId == 18 || typeId == 19 || typeId == 21
            || typeId == 33 || typeId == 37;
    }

    function _compatibleAccessory(uint8 accessory, uint8 typeId, uint256 serial) private pure returns (uint8) {
        if (_isFlameWaterOnlyType(typeId) && !_isFlameOrWaterAccessory(accessory)) {
            return _flameWaterFallbackAccessory(serial);
        }
        if (typeId == STUX_TYPE_ID && accessory == QUESTION_ACCESSORY_ID) {
            return _stuxFallbackAccessory(serial);
        }
        if (_isBodyBlockedAccessory(accessory) && _isHaloBlockedType(typeId)) {
            return _bodyBlockedFallbackAccessory(serial);
        }
        if (accessory == SQUIGGLE_ACCESSORY_ID && _isSquiggleBlockedType(typeId)) {
            return _bodyBlockedFallbackAccessory(serial);
        }
        return accessory;
    }

    function _isFlameWaterOnlyType(uint8 typeId) private pure returns (bool) {
        return typeId == 3 || typeId == 5 || typeId == 7 || typeId == 19 || typeId == 21 || typeId == 33 || typeId == 37;
    }

    function _isFlameOrWaterAccessory(uint8 accessory) private pure returns (bool) {
        return accessory == FLAME_ACCESSORY_ID || accessory == WATER_ACCESSORY_ID;
    }

    function _flameWaterFallbackAccessory(uint256 serial) private pure returns (uint8) {
        return _permute(serial, 2) == 0 ? FLAME_ACCESSORY_ID : WATER_ACCESSORY_ID;
    }

    function _stuxFallbackAccessory(uint256 serial) private pure returns (uint8) {
        return uint8(STUX_FALLBACK_ACCESSORY_SLOTS[_permute(serial, STUX_FALLBACK_ACCESSORY_COUNT)]);
    }

    function _bodyBlockedFallbackAccessory(uint256 serial) private pure returns (uint8) {
        return uint8(BODY_BLOCKED_FALLBACK_ACCESSORY_SLOTS[_permute(serial, BODY_BLOCKED_FALLBACK_ACCESSORY_COUNT)]);
    }

    function _rgbcmyRollSlot(uint256 seed, uint256 objectId, bytes32 salt) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(salt, seed, objectId))) % 100;
    }

    function _permute(uint256 index, uint256 modulus) private pure returns (uint256) {
        return (index * 1_234_567 + uint256(keccak256("TEST_TRAIT_PERMUTATION_V3"))) % modulus;
    }

    function _traitScheduleIndex(uint256 seed, uint256 objectId) private pure returns (uint256) {
        uint256 multiplier = (uint256(keccak256(abi.encodePacked("TEST_TRAIT_INDEX_A_V3", seed))) % 10_000) | 1;
        while (multiplier % 5 == 0) multiplier += 2;
        uint256 offset = uint256(keccak256(abi.encodePacked("TEST_TRAIT_INDEX_B_V3", seed))) % 10_000;
        return (((objectId - 1) % 10_000) * multiplier + offset) % 10_000;
    }
}
