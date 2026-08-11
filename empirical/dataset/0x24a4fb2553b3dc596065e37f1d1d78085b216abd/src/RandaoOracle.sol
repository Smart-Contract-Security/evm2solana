// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RLP} from "@openzeppelin-v5/contracts/utils/RLP.sol";
import {Memory} from "@openzeppelin-v5/contracts/utils/Memory.sol";
import {SafeCast} from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {BlockHashLib} from "solady/src/utils/BlockHashLib.sol";

import {BeaconBlockhashVerifier} from "./BeaconBlockhashVerifier.sol";

/// @notice Permissionless cache for execution-layer prevRandao values.
///
/// Recent path:
///   RLP execution header -> BlockHashLib blockhash/EIP-2935 check
///   -> read header field 13 as prevRandao.
///
/// Long-range path:
///   EIP-4788/beacon-history proof -> old execution block hash
///   -> require keccak256(RLP execution header) == proven block hash
///   -> read header field 13 as prevRandao.
///
/// Owner power and its (bounded) blast radius:
///   The owner can swap `beaconBlockhashVerifier` — intended as a forward path
///   for a future fork that changes the beacon SSZ layout, since the verifier
///   is pinned to a schema and must be replaced rather than mutated. This power
///   is deliberately limited:
///     * It cannot rewrite history. Cached values are append-only (every cache
///       function short-circuits if the block is already set), so a swapped
///       verifier only affects blocks that are *not yet cached*.
///     * It cannot touch the recent path. `proveRecent`/`cacheRecentPrevRandao`
///       use BlockHashLib, never the verifier, so the main path is unaffected.
///   Anyone who does not trust the owner can therefore cache the prevRandao
///   values they need (via either path) before any swap, and those values are
///   then immutable.
contract RandaoOracle is Ownable {
    using SafeCast for uint256;

    /// @dev EIP-2935 serves the hashes of the most recent 8191 ancestor blocks,
    ///      which is exactly the range BlockHashLib (the recent path) can
    ///      resolve. Beyond it, callers must use the beacon-history path.
    uint256 public constant RECENT_WINDOW = 8191;

    BeaconBlockhashVerifier public beaconBlockhashVerifier;

    mapping(uint256 blockNumber => bytes32 prevRandao) public prevRandaoAt;

    event PrevRandaoCached(uint256 indexed blockNumber, bytes32 prevRandao);
    event BeaconBlockhashVerifierUpdated(
        BeaconBlockhashVerifier indexed previous, BeaconBlockhashVerifier indexed next
    );

    error ZeroBeaconBlockhashVerifier();
    error ZeroOwner();
    error MissingRandao(uint256 blockNumber);
    error HeaderHashMismatch(bytes32 expected, bytes32 actual);

    constructor(address initialOwner, BeaconBlockhashVerifier beaconBlockhashVerifier_) {
        require(initialOwner != address(0), ZeroOwner());
        _initializeOwner(initialOwner);
        _setBeaconBlockhashVerifier(beaconBlockhashVerifier_);
    }

    /// @notice Replace the beacon blockhash verifier (e.g. to track a fork that
    ///         changed the beacon SSZ layout). Does not affect already-cached
    ///         values or the recent path. See the contract notes for the trust
    ///         model.
    function setBeaconBlockhashVerifier(BeaconBlockhashVerifier beaconBlockhashVerifier_) external onlyOwner {
        _setBeaconBlockhashVerifier(beaconBlockhashVerifier_);
    }

    function _setBeaconBlockhashVerifier(BeaconBlockhashVerifier beaconBlockhashVerifier_) internal {
        require(address(beaconBlockhashVerifier_) != address(0), ZeroBeaconBlockhashVerifier());
        emit BeaconBlockhashVerifierUpdated(beaconBlockhashVerifier, beaconBlockhashVerifier_);
        beaconBlockhashVerifier = beaconBlockhashVerifier_;
    }

    /// @notice Returns a cached value, reverting if this block has not been cached.
    function getCachedPrevRandao(uint256 blockNumber) external view returns (bytes32 prevRandao) {
        prevRandao = prevRandaoAt[blockNumber];
        require(prevRandao != bytes32(0), MissingRandao(blockNumber));
    }

    /// @notice Whether this block has a cached prevRandao value. Treats zero
    ///         as missing.
    function hasPrevRandao(uint256 blockNumber) external view returns (bool) {
        return prevRandaoAt[blockNumber] != bytes32(0);
    }

    /// @notice Whether the recent path (`cacheRecentPrevRandao`) can serve
    ///         `blockNumber` right now. This is time-dependent: a block near the
    ///         edge can age out before a later tx lands, so treat it as a hint.
    ///         The recent path fails safe (reverts) if the block is out of
    ///         window, in which case the beacon-history path is the fallback.
    ///         Current and future blocks return false.
    function isWithinRecentWindow(uint256 blockNumber) public view returns (bool) {
        return blockNumber < block.number && block.number - blockNumber <= RECENT_WINDOW;
    }

    /// @notice Verifies a recent block header and returns its prevRandao
    ///         without reading or writing the cache.
    function getRecentPrevRandao(uint256 blockNumber, bytes calldata headerRlp)
        public
        view
        returns (bytes32 prevRandao)
    {
        BlockHashLib.verifyBlock(headerRlp, blockNumber);
        prevRandao = _prevRandaoFromHeader(headerRlp);
    }

    /// @notice Verifies a recent block header, caches its prevRandao, and
    ///         returns it. If the block is already cached, returns the cached
    ///         value without re-verifying. The early SLOAD is free in the
    ///         uncached case: it warms the slot, so the cold-access cost is
    ///         paid by the SLOAD instead of by the later SSTORE, not on top.
    function cacheRecentPrevRandao(uint256 blockNumber, bytes calldata headerRlp)
        external
        returns (bytes32 prevRandao)
    {
        prevRandao = prevRandaoAt[blockNumber];
        if (prevRandao != bytes32(0)) return prevRandao;
        prevRandao = getRecentPrevRandao(blockNumber, headerRlp);
        _cache(blockNumber, prevRandao);
    }

    /// @notice Verifies a beacon-history blockhash proof plus matching
    ///         execution header and returns prevRandao without reading or
    ///         writing the cache.
    function getHistoricalBlockhashPrevRandao(uint256 blockNumber, bytes calldata headerRlp, bytes calldata proof)
        public
        view
        returns (bytes32 prevRandao)
    {
        // Block numbers are uint256 throughout; the verifier's ABI still takes a
        // uint64, so narrow only at this boundary (we don't edit that contract).
        // Checked SafeCast: a block number past 2^64 reverts rather than wrapping.
        bytes32 blockHash = beaconBlockhashVerifier.verifyBlockHash(blockNumber.toUint64(), proof);
        bytes32 actual = keccak256(headerRlp);
        require(actual == blockHash, HeaderHashMismatch(blockHash, actual));
        prevRandao = _prevRandaoFromHeader(headerRlp);
    }

    /// @notice Verifies a beacon-history blockhash proof plus matching
    ///         execution header, caches prevRandao, and returns it. If the
    ///         block is already cached, returns the cached value without
    ///         running the (~76k gas) SSZ verification. See
    ///         `cacheRecentPrevRandao` for why the early SLOAD is free in the
    ///         uncached case.
    function cacheHistoricalBlockhashPrevRandao(uint256 blockNumber, bytes calldata headerRlp, bytes calldata proof)
        external
        returns (bytes32 prevRandao)
    {
        prevRandao = prevRandaoAt[blockNumber];
        if (prevRandao != bytes32(0)) return prevRandao;
        prevRandao = getHistoricalBlockhashPrevRandao(blockNumber, headerRlp, proof);
        _cache(blockNumber, prevRandao);
    }

    function _prevRandaoFromHeader(bytes calldata headerRlp) internal pure returns (bytes32 prevRandao) {
        Memory.Slice[] memory fields = RLP.decodeList(headerRlp);
        return RLP.readBytes32(fields[13]);
    }

    function _cache(uint256 blockNumber, bytes32 prevRandao) internal {
        prevRandaoAt[blockNumber] = prevRandao;
        emit PrevRandaoCached(blockNumber, prevRandao);
    }
}
