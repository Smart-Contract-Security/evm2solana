// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct AlbumConfig {
    string name;
    string upc;
    uint8 totalSongs;
    uint64 releaseDate;
    bool isConfigured;
}

struct SongConfig {
    string name;
    string isrc;
    uint8 albumId;
    uint8 totalStems;
    uint256 requiredStemMask;
    uint64 releaseDate;
    bool isConfigured;
}

interface IStems {
    function decodeTokenId(uint256 tokenId) external pure returns (
        uint8 tokenType,
        uint8 albumId,
        uint8 songId,
        uint256 bitmap
    );

    function encodeTokenId(
        uint8 tokenType,
        uint8 albumId,
        uint8 songId,
        uint256 bitmap
    ) external pure returns (uint256);

    function getSongConfig(uint8 albumId, uint8 songId) external view returns (SongConfig memory);

    function getAlbumConfig(uint8 albumId) external view returns (AlbumConfig memory);

    function balanceOf(address account, uint256 id) external view returns (uint256);

    // Public state variable getters
    function mintStartTime() external view returns (uint256);
    function mintEndTime() external view returns (uint256);
    function totalUnrevealedMinted() external view returns (uint256);
    function totalRevealed() external view returns (uint256);
    function totalSongsForged() external view returns (uint256);
    function totalAlbumsForged() external view returns (uint256);

    // Auto-generated getters for public mappings (return individual fields, not structs)
    function albumConfigs(uint8 albumId) external view returns (
        string memory name,
        string memory upc,
        uint8 totalSongs,
        uint64 releaseDate,
        bool isConfigured
    );

    function songConfigs(uint8 albumId, uint8 songId) external view returns (
        string memory name,
        string memory isrc,
        uint8 albumIdField,
        uint8 totalStems,
        uint256 requiredStemMask,
        uint64 releaseDate,
        bool isConfigured
    );

    // ERC1155Supply
    function totalSupply(uint256 id) external view returns (uint256);
}

contract StemsValidator {
    uint8 public constant TYPE_UNREVEALED = 0;
    uint8 public constant TYPE_STEM = 1;
    uint8 public constant TYPE_SONG = 2;
    uint8 public constant TYPE_ALBUM = 3;

    struct ForgeValidationResult {
        bool isValid;
        string errorMessage;
        uint8 resultType;
        uint8 resultAlbum;
        uint8 resultSong;
        uint256 resultBitmap;
        uint256 resultTokenId;
        uint8 completionPercentage;
    }

    IStems public immutable stems;

    constructor(address _stems) {
        stems = IStems(_stems);
    }

    // ============ Moved View Functions ============

    function getTokenInfo(uint256 tokenId) external view returns (
        uint8 tokenType,
        uint8 albumId,
        uint8 songId,
        uint256 bitmap,
        uint8 completionPercentage,
        bool isComplete,
        string memory tokenTypeName,
        string memory albumName,
        string memory songName
    ) {
        (tokenType, albumId, songId, bitmap) = stems.decodeTokenId(tokenId);

        if (tokenType == TYPE_UNREVEALED) {
            return (tokenType, 0, 0, 0, 0, false, "Unrevealed", "", "");
        }

        (, , , , bool albumConfigured) = stems.albumConfigs(albumId);
        if (albumConfigured) {
            (albumName, , , ,) = stems.albumConfigs(albumId);
        }

        if (tokenType == TYPE_STEM || tokenType == TYPE_SONG) {
            (, , , , , , bool songConfigured) = stems.songConfigs(albumId, songId);
            if (songConfigured) {
                (string memory sName, , , uint8 totalStems, uint256 requiredStemMask, ,) = stems.songConfigs(albumId, songId);
                songName = sName;
                uint256 stemCount = _countBits(bitmap);
                completionPercentage = uint8((stemCount * 100) / totalStems);
                isComplete = (bitmap == requiredStemMask);
            }
            tokenTypeName = tokenType == TYPE_STEM ? "Stem" : "Song";
        } else if (tokenType == TYPE_ALBUM) {
            uint256 songCount = _countBits(bitmap);
            if (albumConfigured) {
                (, , uint8 totalSongs, ,) = stems.albumConfigs(albumId);
                completionPercentage = uint8((songCount * 100) / totalSongs);
                isComplete = (songCount == totalSongs);
            }
            tokenTypeName = "Album";
        }
    }

    function getStemsInToken(uint256 tokenId) external view returns (uint8[] memory stemBits) {
        (, , , uint256 bitmap) = stems.decodeTokenId(tokenId);

        uint256 count = _countBits(bitmap);
        stemBits = new uint8[](count);

        uint256 index = 0;
        for (uint8 i = 0; i < 232 && index < count; i++) {
            if ((bitmap & (1 << i)) != 0) {
                stemBits[index++] = i;
            }
        }
    }

    function getStemsNeededForSong(
        uint8 albumId,
        uint8 songId,
        uint256 currentBitmap
    ) external view returns (uint256 missingBitmap, uint8[] memory missingStems) {
        (, , , , uint256 requiredStemMask, ,) = stems.songConfigs(albumId, songId);
        missingBitmap = requiredStemMask & ~currentBitmap;

        uint256 count = _countBits(missingBitmap);
        missingStems = new uint8[](count);

        uint256 index = 0;
        for (uint8 i = 0; i < 232 && index < count; i++) {
            if ((missingBitmap & (1 << i)) != 0) {
                missingStems[index++] = i;
            }
        }
    }

    function getMintStats() external view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 totalMinted,
        uint256 revealed,
        uint256 unrevealed,
        bool isActive
    ) {
        return (
            stems.mintStartTime(),
            stems.mintEndTime(),
            stems.totalUnrevealedMinted(),
            stems.totalRevealed(),
            stems.totalSupply(0),
            isMintActive()
        );
    }

    function getSupplyStats() external view returns (
        uint256 totalUnrevealed,
        uint256 totalStemsRevealed,
        uint256 unrevealedSupply,
        uint256 songsForged,
        uint256 albumsForged
    ) {
        totalUnrevealed = stems.totalUnrevealedMinted();
        totalStemsRevealed = stems.totalRevealed();
        unrevealedSupply = stems.totalSupply(0);
        songsForged = stems.totalSongsForged();
        albumsForged = stems.totalAlbumsForged();
    }

    function getAllSongsForAlbum(uint8 albumId) external view returns (SongConfig[] memory songs) {
        AlbumConfig memory album = stems.getAlbumConfig(albumId);

        songs = new SongConfig[](album.totalSongs);

        for (uint8 i = 0; i < album.totalSongs; i++) {
            (
                string memory name,
                string memory isrc,
                uint8 aId,
                uint8 totalStems,
                uint256 requiredStemMask,
                uint64 releaseDate,
                bool isConfigured
            ) = stems.songConfigs(albumId, i);
            songs[i] = SongConfig({
                name: name,
                isrc: isrc,
                albumId: aId,
                totalStems: totalStems,
                requiredStemMask: requiredStemMask,
                releaseDate: releaseDate,
                isConfigured: isConfigured
            });
        }
    }

    function isMintActive() public view returns (bool) {
        uint256 startTime = stems.mintStartTime();
        uint256 endTime = stems.mintEndTime();
        return startTime > 0 &&
               block.timestamp >= startTime &&
               block.timestamp <= endTime;
    }

    function getMintTimeRemaining() public view returns (uint256) {
        uint256 startTime = stems.mintStartTime();
        uint256 endTime = stems.mintEndTime();
        if (startTime == 0) return 0;
        if (block.timestamp >= endTime) return 0;
        if (block.timestamp < startTime) return endTime - startTime;
        return endTime - block.timestamp;
    }

    /**
     * @notice Seconds remaining until the mint window opens.
     * @return 0 if mint hasn't been scheduled yet OR if it's already open / ended.
     */
    function getTimeUntilMintStarts() public view returns (uint256) {
        uint256 startTime = stems.mintStartTime();
        if (startTime == 0) return 0;
        if (block.timestamp >= startTime) return 0;
        return startTime - block.timestamp;
    }

    // ============ Forge Validation ============

    function validateForge(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address owner
    ) external view returns (ForgeValidationResult memory result) {
        if (tokenIds.length != amounts.length) {
            return _invalidResult("Array length mismatch");
        }
        if (tokenIds.length == 0) {
            return _invalidResult("No tokens provided");
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (amounts[i] != 1) {
                return _invalidResult("Amounts must be 1");
            }
        }

        (uint8 firstType, uint8 album, uint8 song, ) = stems.decodeTokenId(tokenIds[0]);

        if (firstType == TYPE_UNREVEALED) {
            return _invalidResult("Cannot forge unrevealed tokens");
        }

        if (firstType == TYPE_STEM) {
            result = _validateStemForge(tokenIds, album, song);
        } else {
            result = _validateSongAlbumForge(tokenIds, album);
        }

        if (!result.isValid) {
            return result;
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (stems.balanceOf(owner, tokenIds[i]) < amounts[i]) {
                return _invalidResult("Insufficient token balance");
            }
        }

        return result;
    }

    function _invalidResult(string memory error) internal pure returns (ForgeValidationResult memory) {
        ForgeValidationResult memory result;
        result.isValid = false;
        result.errorMessage = error;
        return result;
    }

    function _validateStemForge(
        uint256[] calldata tokenIds,
        uint8 targetAlbum,
        uint8 targetSong
    ) internal view returns (ForgeValidationResult memory result) {
        // H-4: Return error instead of reverting for unconfigured songs
        SongConfig memory songConfig;
        try stems.getSongConfig(targetAlbum, targetSong) returns (SongConfig memory sc) {
            songConfig = sc;
        } catch {
            return _invalidResult("Song not configured");
        }

        uint256 combinedBitmap = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint8 tType, uint8 tAlbum, uint8 tSong, uint256 tBitmap) = stems.decodeTokenId(tokenIds[i]);

            if (tType != TYPE_STEM) {
                return _invalidResult("Cannot mix STEM with SONG/ALBUM tokens");
            }
            if (tAlbum != targetAlbum) {
                return _invalidResult("Stems from different albums cannot be combined");
            }
            if (tSong != targetSong) {
                return _invalidResult("Stems from different songs cannot be combined");
            }

            // H-3: Validate bitmap contains only valid stems for this song
            if ((tBitmap & ~songConfig.requiredStemMask) != 0) {
                return _invalidResult("Stem not valid for this song");
            }

            combinedBitmap |= tBitmap;
        }

        bool isComplete = (combinedBitmap == songConfig.requiredStemMask);

        result.isValid = true;
        result.resultType = isComplete ? TYPE_SONG : TYPE_STEM;
        result.resultAlbum = targetAlbum;
        result.resultSong = targetSong;
        result.resultBitmap = combinedBitmap;
        result.resultTokenId = stems.encodeTokenId(result.resultType, targetAlbum, targetSong, combinedBitmap);
        result.completionPercentage = uint8((_countBits(combinedBitmap) * 100) / songConfig.totalStems);
        result.errorMessage = isComplete ? "Will create complete SONG token" : "Will create combined STEM token";

        return result;
    }

    function _validateSongAlbumForge(
        uint256[] calldata tokenIds,
        uint8 targetAlbum
    ) internal view returns (ForgeValidationResult memory result) {
        // H-4: Return error instead of reverting for unconfigured albums
        AlbumConfig memory albumConfig;
        try stems.getAlbumConfig(targetAlbum) returns (AlbumConfig memory ac) {
            albumConfig = ac;
        } catch {
            return _invalidResult("Album not configured");
        }

        uint256 songBitmap = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint8 tType, uint8 tAlbum, uint8 tSong, uint256 tBitmap) = stems.decodeTokenId(tokenIds[i]);

            if (tAlbum != targetAlbum) {
                return _invalidResult("All tokens must be from the same album");
            }

            if (tType == TYPE_STEM) {
                return _invalidResult("Cannot combine STEM with SONG/ALBUM tokens");
            } else if (tType == TYPE_SONG) {
                SongConfig memory songConfig;
                try stems.getSongConfig(tAlbum, tSong) returns (SongConfig memory sc) {
                    songConfig = sc;
                } catch {
                    return _invalidResult("Song not configured");
                }
                if (tBitmap != songConfig.requiredStemMask) {
                    return _invalidResult("Song must be 100% complete");
                }
                songBitmap |= (1 << tSong);
            } else if (tType == TYPE_ALBUM) {
                songBitmap |= tBitmap;
            }
        }

        uint256 songCount = _countBits(songBitmap);

        if (songCount == 0) {
            return _invalidResult("At least one song required");
        }

        bool isComplete = (songCount == albumConfig.totalSongs);

        result.isValid = true;
        result.resultType = TYPE_ALBUM;
        result.resultAlbum = targetAlbum;
        result.resultSong = 0;
        result.resultBitmap = songBitmap;
        result.resultTokenId = stems.encodeTokenId(TYPE_ALBUM, targetAlbum, 0, songBitmap);
        result.completionPercentage = uint8((songCount * 100) / albumConfig.totalSongs);
        result.errorMessage = isComplete
            ? "Will create complete ALBUM token"
            : "Will create partial ALBUM token";

        return result;
    }

    function _countBits(uint256 bitmap) internal pure returns (uint256 count) {
        while (bitmap != 0) {
            count += bitmap & 1;
            bitmap >>= 1;
        }
    }
}
