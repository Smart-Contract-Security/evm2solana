// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { CoreAccess } from "../base/CoreAccess.sol";
import { INAVOracle } from "../interfaces/INAVOracle.sol";
import { PriceEntry, SignedPriceBundle } from "../interfaces/Types.sol";
import { FixedPoint } from "../libraries/FixedPoint.sol";
import { Roles } from "../libraries/Roles.sol";

interface ICoreVaultAllocation {
    function getTargetAllocation() external view returns (address[] memory tokens, uint256[] memory weights);
}

/// @title NAVOracle
/// @dev  push-on-touch model
contract NAVOracle is CoreAccess, INAVOracle {
    using ECDSA for bytes32;

    bytes32 public constant PRICE_ENTRY_TYPEHASH =
        keccak256("PriceEntry(address asset,uint256 price,uint8 priceDecimals,uint64 asOfTimestamp)");
    bytes32 public constant BUNDLE_TYPEHASH = keccak256(
        "SignedPriceBundle(uint64 round,uint64 deadline,PriceEntry[] entries,bytes32 assetSetDigest)PriceEntry(address asset,uint256 price,uint8 priceDecimals,uint64 asOfTimestamp)"
    );

    //EIP712_DOMAIN_TYPEHASH =
    //                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    //        = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f
    //NAV_ORACLE_NAME_HASH =
    //                    keccak256("CoreVault-NAVOracle")
    //        = 0xaea4d67c2e12725f70eba049f95c5c59c259832263d438ed502ac220001bbc42

    //NAV_ORACLE_VERSION_HASH =
    //                    keccak256("1")
    //        = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6

    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
            0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    bytes32 public constant NAV_ORACLE_NAME_HASH =
        0xaea4d67c2e12725f70eba049f95c5c59c259832263d438ed502ac220001bbc42;
    bytes32 public constant NAV_ORACLE_VERSION_HASH =
        0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    uint256 public maxStaleness;
    uint256 public maxRoundJump;
    address public coreVault;

    uint64 private _latestRound;
    mapping(uint256 => bytes32) private _bundleHashByRound;
    mapping(address => uint256) private _priceByAsset;
    mapping(address => bool) public trustedSigner;
    mapping(address => bool) public authorizedCaller;
    bool private _navOracleInitialized;

    event PriceBundleIngested(uint64 indexed round, address indexed signer);
    event TrustedSignerSet(address indexed signer, bool trusted);
    event AuthorizedCallerSet(address indexed caller, bool authorized);
    event CoreVaultSet(address indexed coreVault);
    event MaxRoundJumpSet(uint256 maxRoundJump);

    constructor(address admin, uint256 maxStaleness_, uint256 maxRoundJump_)
        CoreAccess(admin)
    {
        if (admin != address(0)) _initializeNavOracle(maxStaleness_, maxRoundJump_);
    }

    function initialize(address admin, uint256 maxStaleness_, uint256 maxRoundJump_) external {
        _initializeCoreAccess(admin);
        _initializeNavOracle(maxStaleness_, maxRoundJump_);
    }

    function _initializeNavOracle(uint256 maxStaleness_, uint256 maxRoundJump_) internal {
        require(!_navOracleInitialized, "NAVOracle: initialized");
        require(maxStaleness_ > 0 && maxRoundJump_ > 0, "NAVOracle: bad params");
        _navOracleInitialized = true;
        maxStaleness = maxStaleness_;
        maxRoundJump = maxRoundJump_;
    }

    function setTrustedSigner(address signer, bool trusted) external onlyAdmin {
        trustedSigner[signer] = trusted;
        emit TrustedSignerSet(signer, trusted);
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyAdmin {
        authorizedCaller[caller] = authorized;
        emit AuthorizedCallerSet(caller, authorized);
    }

    function setCoreVault(address coreVault_) external onlyAdmin {
        require(coreVault_ != address(0), "NAVOracle: zero core vault");
        coreVault = coreVault_;
        emit CoreVaultSet(coreVault_);
    }

    function setMaxRoundJump(uint256 maxRoundJump_) external onlyAdmin {
        require(maxRoundJump_ > 0, "NAVOracle: bad params");
        maxRoundJump = maxRoundJump_;
        emit MaxRoundJumpSet(maxRoundJump_);
    }

    function ingest(SignedPriceBundle calldata bundle) external returns (uint64 round) {
        require(
            (authorizedCaller[msg.sender] && hasRole(Roles.NAV_CALLER, msg.sender))
                || hasRole(Roles.OPERATOR, msg.sender),
            "NAVOracle: unauthorized caller"
        );
        require(block.timestamp <= bundle.deadline, "NAVOracle: expired");
        (address[] memory tokens, uint256[] memory weights) = _targetAllocation(msg.sender);
        _validateAssetSet(bundle, tokens, weights);
        bytes32 bundleHash = hashBundle(bundle);
        address recovered = bundleHash.recover(bundle.v, bundle.r, bundle.s);
        require(recovered == bundle.signer && trustedSigner[recovered], "NAVOracle: bad signer");

        if (bundle.round == _latestRound && _latestRound != 0) {
            require(_bundleHashByRound[bundle.round] == bundleHash, "NAVOracle: round changed");
            return bundle.round;
        }

        require(bundle.round > _latestRound, "NAVOracle: old round");
        if (_latestRound != 0) {
            require(maxRoundJump <= type(uint64).max, "NAVOracle: round jump overflow");
            // casting to 'uint64' is safe because maxRoundJump is checked above.
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bundle.round <= _latestRound + uint64(maxRoundJump), "NAVOracle: round jump");
        }
        _validateBundleTimestamps(bundle);
        for (uint256 i; i < bundle.entries.length; ++i) {
            PriceEntry calldata entry = bundle.entries[i];
            _priceByAsset[entry.asset] = _normalizePrice(entry.price, entry.priceDecimals);
        }

        _latestRound = bundle.round;
        _bundleHashByRound[bundle.round] = bundleHash;
        emit PriceBundleIngested(bundle.round, recovered);
        return bundle.round;
    }

    function latestRound() external view returns (uint64) {
        return _latestRound;
    }

    function priceOf(address asset_) external view returns (uint256) {
        return _priceByAsset[asset_];
    }

    /// @notice EIP-712
    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorHash(block.chainid, address(this));
    }

    function hashBundle(SignedPriceBundle calldata bundle) public view returns (bytes32) {
        bytes32[] memory entryHashes = new bytes32[](bundle.entries.length);
        for (uint256 i; i < bundle.entries.length; ++i) {
            PriceEntry calldata entry = bundle.entries[i];
            // PriceEntry(address asset,uint256 price,uint8 priceDecimals,uint64 asOfTimestamp) 的 hash。
            // forge-lint: disable-next-line(asm-keccak256)
            entryHashes[i] = keccak256(
                abi.encode(PRICE_ENTRY_TYPEHASH, entry.asset, entry.price, entry.priceDecimals, entry.asOfTimestamp)
            );
        }
        bytes32 entriesHash = _hashEntryHashes(entryHashes);
        bytes32 structHash =
            _bundleStructHash(BUNDLE_TYPEHASH, bundle.round, bundle.deadline, entriesHash, bundle.assetSetDigest);
        return ECDSA.toTypedDataHash(domainSeparator(), structHash);
    }

    function recoverBundleSigner(SignedPriceBundle calldata bundle)
        external
        view
        returns (bytes32 digest, address recovered, bool signerMatches, bool recoveredTrusted)
    {
        digest = hashBundle(bundle);
        recovered = digest.recover(bundle.v, bundle.r, bundle.s);
        signerMatches = recovered == bundle.signer;
        recoveredTrusted = trustedSigner[recovered];
    }

    function recomputeTotalAssetsFromBundle(
        address vault,
        address usdc,
        SignedPriceBundle calldata bundle
    ) external view returns (uint256 totalAssetsValue) {
        require(block.timestamp <= bundle.deadline, "NAVOracle: expired");
        (address[] memory tokens, uint256[] memory weights) = _targetAllocation(vault);
        _validateAssetSet(bundle, tokens, weights);
        bytes32 bundleHash = hashBundle(bundle);
        address recovered = bundleHash.recover(bundle.v, bundle.r, bundle.s);
        require(recovered == bundle.signer && trustedSigner[recovered], "NAVOracle: bad signer");
        _validateBundleTimestamps(bundle);

        totalAssetsValue = FixedPoint.usdcToWad(IERC20(usdc).balanceOf(vault));
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == usdc) continue;
            uint256 balance = IERC20(token).balanceOf(vault);
            if (balance == 0) continue;
            uint256 price = _priceInBundle(bundle, token);
            require(price > 0, "NAVOracle: missing price");
            totalAssetsValue += balance * price / _assetUnit(token);
        }
    }

    function _hashEntryHashes(bytes32[] memory entryHashes) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            result := keccak256(add(entryHashes, 0x20), mul(mload(entryHashes), 0x20))
        }
    }

    function _domainSeparatorHash(uint256 chainId, address verifyingContract) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, EIP712_DOMAIN_TYPEHASH)
            mstore(add(ptr, 0x20), NAV_ORACLE_NAME_HASH)
            mstore(add(ptr, 0x40), NAV_ORACLE_VERSION_HASH)
            mstore(add(ptr, 0x60), chainId)
            mstore(add(ptr, 0x80), and(verifyingContract, 0xffffffffffffffffffffffffffffffffffffffff))
            result := keccak256(ptr, 0xa0)
        }
    }

    function _bundleStructHash(
        bytes32 typehash,
        uint64 round,
        uint64 deadline,
        bytes32 entriesHash,
        bytes32 digest
    ) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, typehash)
            mstore(add(ptr, 0x20), round)
            mstore(add(ptr, 0x40), deadline)
            mstore(add(ptr, 0x60), entriesHash)
            mstore(add(ptr, 0x80), digest)
            result := keccak256(ptr, 0xa0)
        }
    }

    function _normalizePrice(uint256 price, uint8 priceDecimals) internal pure returns (uint256 normalized) {
        require(price > 0, "NAVOracle: zero price");
        require(priceDecimals <= 36, "NAVOracle: bad price decimals");
        if (priceDecimals == 18) normalized = price;
        else if (priceDecimals < 18) normalized = price * (10 ** uint256(18 - priceDecimals));
        else normalized = price / (10 ** uint256(priceDecimals - 18));
        require(normalized > 0, "NAVOracle: zero normalized price");
    }

    function _validatePriceTimestamp(uint64 asOfTimestamp) internal view {
        require(asOfTimestamp <= block.timestamp, "NAVOracle: future price");
        require(block.timestamp <= uint256(asOfTimestamp) + maxStaleness, "NAVOracle: stale price");
    }

    function _validateBundleTimestamps(SignedPriceBundle calldata bundle) internal view {
        for (uint256 i; i < bundle.entries.length; ++i) {
            _validatePriceTimestamp(bundle.entries[i].asOfTimestamp);
        }
    }

    function _targetAllocation(address sourceHint)
        internal
        view
        returns (address[] memory tokens, uint256[] memory weights)
    {
        address source = coreVault == address(0) ? sourceHint : coreVault;
        require(source != address(0), "NAVOracle: core vault unset");
        return ICoreVaultAllocation(source).getTargetAllocation();
    }

    function _validateAssetSet(
        SignedPriceBundle calldata bundle,
        address[] memory tokens,
        uint256[] memory weights
    ) internal pure {
        require(tokens.length != 0 && bundle.entries.length == tokens.length, "NAVOracle: bad asset entries");
        require(bundle.assetSetDigest == keccak256(abi.encode(tokens, weights)), "NAVOracle: bad asset set");
        for (uint256 i; i < tokens.length; ++i) {
            require(bundle.entries[i].asset == tokens[i], "NAVOracle: bad asset entries");
        }
    }

    function _priceInBundle(SignedPriceBundle calldata bundle, address asset_) internal pure returns (uint256) {
        for (uint256 i; i < bundle.entries.length; ++i) {
            PriceEntry calldata entry = bundle.entries[i];
            if (entry.asset == asset_) return _normalizePrice(entry.price, entry.priceDecimals);
        }
        return 0;
    }

    function _assetUnit(address token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= 36, "NAVOracle: bad decimals");
        return 10 ** uint256(decimals);
    }
}
