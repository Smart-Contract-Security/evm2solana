// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IPTBridge} from "./interfaces/IPTBridge.sol";
import {IBridgeMessenger} from "./interfaces/IBridgeMessenger.sol";
import {BridgeMessages} from "./libraries/BridgeMessages.sol";
import {StellarAddressValidator} from "./libraries/StellarAddressValidator.sol";
import {WrappedStellarPT} from "./WrappedStellarPT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title IPrincipalToken
 * @notice Minimal interface for Spectra Principal Token
 */
interface IPrincipalToken is IERC20, IERC20Metadata {
    function maturity() external view returns (uint256);
    function underlying() external view returns (address);
}

/**
 * @title PTBridge
 * @author Spectra Finance
 * @notice Bridge contract for Spectra Principal Tokens between EVM chains and Stellar
 * @dev Uses a modular messenger pattern to allow swapping cross-chain protocols.
 *      Uses Transparent proxy pattern for upgradeability and AccessManager for permissions.
 *
 * @custom:security-contact security@spectra.finance
 */
contract PTBridge is
    IPTBridge,
    Initializable,
    AccessManagedUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // =============================================================
    //                           STORAGE
    // =============================================================

    IBridgeMessenger public messenger;
    string public stellarChain;

    mapping(address => uint256) private _lockedBalances;
    /// @notice Trusted remote messenger address on the Stellar destination chain.
    ///         Same value is enforced as the inbound `source_address` on
    ///         `receiveMessage` and used as the outbound destination in
    ///         `bridgeToStellar` / `bridgeStellarPtBack` / `estimateBridgeCost`.
    string public trustedRemote;

    /// @notice Previous-era messenger and its per-chain trusted remotes,
    ///         populated atomically by `migrateMessenger`. Grouped in a
    ///         struct because the two fields are only meaningful together:
    ///         the previous messenger's encoded sender address only matches
    ///         under the trusted remote captured at migration time.
    struct Previous {
        IBridgeMessenger messenger;
        string trustedRemote;
    }
    Previous internal _previous;

    uint256 private _requestNonce;

    // =============================================================
    //                       FEE CONFIGURATION
    // =============================================================

    uint256 public bridgeFeeBps;
    uint256 public bridgeBackFeeBps;
    uint256 public constant MAX_FEE_BPS = 1000;
    address public feeRecipient;
    mapping(address => uint256) public feesCollected;

    uint256 private constant BPS_DENOMINATOR = 10_000;

    // =============================================================
    //                        RATE LIMITING
    // =============================================================

    mapping(address => int128) public rateLimitPerWindow;
    uint256 public rateLimitWindow;
    mapping(address => int128) private _windowVolume;
    mapping(address => uint256) private _windowStart;
    uint256 public constant DEFAULT_RATE_LIMIT_WINDOW = 3600;

    // =============================================================
    //                  STELLAR NATIVE PT STORAGE
    // =============================================================

    mapping(bytes32 => address) private _wrappedStellarPts;
    address public wrappedPtBeacon;

    /// @notice True once `setRateLimit` has been called for the PT. Lets us
    ///         distinguish "unset" (no limit, matches Stellar's default) from
    ///         the explicit `setRateLimit(pt, 0)` (blocks the PT).
    mapping(address => bool) public rateLimitSet;

    // =============================================================
    //                         MODIFIERS
    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyMessenger() {
        if (
            msg.sender != address(messenger)
                && (address(_previous.messenger) == address(0) || msg.sender != address(_previous.messenger))
        ) {
            revert OnlyMessenger();
        }
        _;
    }

    // =============================================================
    //                       INITIALIZATION
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority_, address beacon_) external initializer {
        require(beacon_ != address(0), "Zero address");
        __AccessManaged_init(authority_);
        __Pausable_init();
        rateLimitWindow = DEFAULT_RATE_LIMIT_WINDOW;
        wrappedPtBeacon = beacon_;
    }

    // =============================================================
    //                      BRIDGE OPERATIONS
    // =============================================================

    /// @inheritdoc IPTBridge
    function bridgeToStellar(
        address pt,
        uint256 amount,
        string calldata stellarRecipient,
        address refundAddress,
        uint256 minAmountOut
    ) external payable nonReentrant whenNotPaused returns (uint256 nonce) {
        if (refundAddress == address(0)) revert InvalidRefundAddress();
        return _bridgeToStellar(pt, amount, stellarRecipient, refundAddress, minAmountOut);
    }

    function _bridgeToStellar(
        address pt,
        uint256 amount,
        string calldata stellarRecipient,
        address refundAddress,
        uint256 minAmountOut
    ) internal returns (uint256 nonce) {
        if (address(messenger) == address(0)) revert MessengerNotSet();
        if (bytes(stellarChain).length == 0) revert EmptyStellarChain();
        if (bytes(trustedRemote).length == 0) revert TrustedRemoteNotSet();
        if (amount == 0) revert ZeroAmount();
        if (bytes(stellarRecipient).length == 0) revert EmptyRecipient();

        if (!StellarAddressValidator.isValidStellarAddress(stellarRecipient)) {
            revert InvalidStellarAddress();
        }

        _checkAndUpdateRateLimit(pt, -_safeToInt128(amount));

        (uint256 feeAmount, uint256 bridgeAmount) = _calculateFee(amount, bridgeFeeBps);
        if (bridgeAmount < minAmountOut) revert MinAmountOutNotMet();

        nonce = _requestNonce++;

        // Note: fee-on-transfer tokens are not supported. The bridge assumes
        // the full `amount` is received. Using such tokens will cause accounting
        // mismatches and failed unlocks.
        IERC20(pt).safeTransferFrom(msg.sender, address(this), amount);
        _lockedBalances[pt] += bridgeAmount;

        if (feeAmount > 0) {
            feesCollected[pt] += feeAmount;
            emit FeeCollected(pt, feeRecipient, feeAmount);
        }

        {
            IPrincipalToken ptToken = IPrincipalToken(pt);
            bytes memory payload = BridgeMessages.encodeBridgeToStellar(
                BridgeMessages.BridgeToStellarMsg({
                    msgType: BridgeMessages.MSG_TYPE_BRIDGE_TO_STELLAR,
                    ptAddress: pt,
                    amount: bridgeAmount,
                    sourceChainId: uint32(block.chainid),
                    stellarRecipient: stellarRecipient,
                    maturity: ptToken.maturity(),
                    underlying: ptToken.underlying(),
                    decimals: ptToken.decimals(),
                    ptSymbol: ptToken.symbol()
                })
            );

            messenger.sendMessage{value: msg.value}(
                stellarChain,
                trustedRemote,
                payload,
                refundAddress
            );
        }

        emit PTLocked(nonce, pt, msg.sender, bridgeAmount, stellarRecipient, uint32(block.chainid));
    }

    function receiveMessage(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external onlyMessenger whenNotPaused nonReentrant {
        // The bridge talks to exactly one destination chain. Reject any
        // inbound that claims a different sourceChain than the configured
        // one — defence-in-depth against a buggy or compromised messenger.
        if (keccak256(bytes(sourceChain)) != keccak256(bytes(stellarChain))) revert UntrustedSource();

        bytes32 sourceHash = keccak256(bytes(sourceAddress));

        bool trustedMatch = bytes(trustedRemote).length > 0 && keccak256(bytes(trustedRemote)) == sourceHash;

        // Accept the previous-era trusted remote during the messenger
        // migration grace period: each messenger encodes the source sender
        // address differently, so in-flight inbound messages from the
        // previous messenger only match against the snapshot taken at
        // migration time.
        string memory prev = _previous.trustedRemote;
        bool prevMatch = bytes(prev).length > 0 && keccak256(bytes(prev)) == sourceHash;

        if (!trustedMatch && !prevMatch) revert UntrustedSource();

        uint8 msgType = BridgeMessages.getMessageType(payload);

        if (msgType == BridgeMessages.MSG_TYPE_BRIDGE_FROM_STELLAR) {
            _processBridgeBackFromStellar(payload);
        } else if (msgType == BridgeMessages.MSG_TYPE_STELLAR_PT_TO_EVM) {
            _processStellarPtToEvm(payload);
        } else {
            revert InvalidMessageType();
        }
    }

    function _processBridgeBackFromStellar(bytes calldata payload) internal {
        BridgeMessages.BridgeFromStellarMsg memory msg_ = BridgeMessages.decodeBridgeFromStellar(payload);

        if (_lockedBalances[msg_.ptAddress] < msg_.amount) {
            revert InsufficientLockedBalance();
        }

        _checkAndUpdateRateLimit(msg_.ptAddress, _safeToInt128(msg_.amount));

        _lockedBalances[msg_.ptAddress] -= msg_.amount;
        IERC20(msg_.ptAddress).safeTransfer(msg_.evmRecipient, msg_.amount);

        emit PTUnlocked(msg_.stellarTxHash, msg_.ptAddress, msg_.evmRecipient, msg_.amount);
    }

    /// @dev Reverts if `value` exceeds type(int128).max (~1.7e38)
    function _safeToInt128(uint256 value) internal pure returns (int128) {
        if (value > uint256(uint128(type(int128).max))) revert AmountExceedsStellarMax();
        return int128(uint128(value));
    }

    function _checkAndUpdateRateLimit(address pt, int128 amount) internal {
        // Symmetric semantics with Stellar:
        //   unset            -> no limit (matches Stellar's i128::MAX default)
        //   type(int128).max -> no limit (short-circuit)
        //   0                -> blocks the PT (any non-zero amount exceeds 0)
        //   v                -> enforced at v
        if (!rateLimitSet[pt]) return;
        int128 limit = rateLimitPerWindow[pt];
        if (limit == type(int128).max) return;

        uint256 windowStart = _windowStart[pt];
        int128 currentVolume = _windowVolume[pt];

        if (block.timestamp >= windowStart + rateLimitWindow) {
            _windowStart[pt] = block.timestamp;
            currentVolume = 0;
        }

        int128 newVolume = currentVolume + amount;
        if (newVolume > limit || newVolume < -limit) revert RateLimitExceeded();
        _windowVolume[pt] = newVolume;
    }

    // =============================================================
    //              STELLAR NATIVE PT BRIDGE OPERATIONS
    // =============================================================

    function _processStellarPtToEvm(bytes calldata payload) internal {
        BridgeMessages.StellarPtToEvmMsg memory msg_ = BridgeMessages.decodeStellarPtToEvm(payload);

        address wrappedToken = _getOrDeployWrappedStellarPt(
            msg_.stellarPtAddress, msg_.maturity, msg_.decimals, msg_.ptSymbol
        );

        _checkAndUpdateRateLimit(wrappedToken, _safeToInt128(msg_.amount));
        WrappedStellarPT(wrappedToken).mint(msg_.evmRecipient, msg_.amount);

        emit StellarPTMinted(
            msg_.stellarTxHash, wrappedToken, msg_.evmRecipient, msg_.amount, msg_.stellarPtAddress
        );
    }

    function _getOrDeployWrappedStellarPt(
        string memory stellarPtAddress,
        uint64 maturity_,
        uint8 decimals_,
        bytes32 ptSymbolBytes
    ) internal returns (address) {
        bytes32 key = keccak256(bytes(stellarPtAddress));
        address existing = _wrappedStellarPts[key];
        if (existing != address(0)) return existing;

        string memory ptSymbol = _bytes32ToString(ptSymbolBytes);
        bytes memory initData = abi.encodeCall(
            WrappedStellarPT.initialize,
            (
                string.concat("Wrapped Stellar ", ptSymbol),
                string.concat("ws", ptSymbol),
                decimals_,
                uint256(maturity_),
                stellarPtAddress,
                address(this)
            )
        );

        address wrappedAddr = address(new BeaconProxy{salt: key}(wrappedPtBeacon, initData));
        _wrappedStellarPts[key] = wrappedAddr;
        emit WrappedStellarPTDeployed(wrappedAddr, stellarPtAddress, uint256(maturity_), ptSymbol);
        return wrappedAddr;
    }

    /// @inheritdoc IPTBridge
    function wrappedStellarPts(string calldata stellarPtAddress) external view returns (address) {
        return _wrappedStellarPts[keccak256(bytes(stellarPtAddress))];
    }

    /// @inheritdoc IPTBridge
    function bridgeStellarPtBack(
        address wrappedToken,
        uint256 amount,
        string calldata stellarRecipient,
        address refundAddress,
        uint256 minAmountOut
    ) external payable nonReentrant whenNotPaused returns (uint256 nonce) {
        if (refundAddress == address(0)) revert InvalidRefundAddress();
        return _bridgeStellarPtBack(wrappedToken, amount, stellarRecipient, refundAddress, minAmountOut);
    }

    function _bridgeStellarPtBack(
        address wrappedToken,
        uint256 amount,
        string calldata stellarRecipient,
        address refundAddress,
        uint256 minAmountOut
    ) internal returns (uint256 nonce) {
        if (address(messenger) == address(0)) revert MessengerNotSet();
        if (bytes(stellarChain).length == 0) revert EmptyStellarChain();
        if (bytes(trustedRemote).length == 0) revert TrustedRemoteNotSet();
        if (amount == 0) revert ZeroAmount();
        if (bytes(stellarRecipient).length == 0) revert EmptyRecipient();

        if (!StellarAddressValidator.isValidStellarAddress(stellarRecipient)) {
            revert InvalidStellarAddress();
        }

        string memory stellarPtAddress = WrappedStellarPT(wrappedToken).stellarPtAddress();
        if (_wrappedStellarPts[keccak256(bytes(stellarPtAddress))] != wrappedToken) revert UnknownWrappedToken();

        _checkAndUpdateRateLimit(wrappedToken, -_safeToInt128(amount));

        (uint256 feeAmount, uint256 bridgeAmount) = _calculateFee(amount, bridgeBackFeeBps);
        if (bridgeAmount < minAmountOut) revert MinAmountOutNotMet();

        IERC20(wrappedToken).safeTransferFrom(msg.sender, address(this), amount);
        WrappedStellarPT(wrappedToken).burn(address(this), bridgeAmount);

        if (feeAmount > 0) {
            feesCollected[wrappedToken] += feeAmount;
            emit FeeCollected(wrappedToken, feeRecipient, feeAmount);
        }

        nonce = _requestNonce++;

        bytes memory payload = BridgeMessages.encodeStellarPtFromEvm(
            BridgeMessages.StellarPtFromEvmMsg({
                msgType: BridgeMessages.MSG_TYPE_STELLAR_PT_FROM_EVM,
                amount: bridgeAmount,
                stellarPtAddress: stellarPtAddress,
                stellarRecipient: stellarRecipient
            })
        );

        messenger.sendMessage{value: msg.value}(stellarChain, trustedRemote, payload, refundAddress);
        emit StellarPTBurned(nonce, wrappedToken, msg.sender, bridgeAmount, stellarRecipient);
    }

    function _bytes32ToString(bytes32 b) internal pure returns (string memory) {
        uint256 len = 0;
        while (len < 32 && b[len] != 0) len++;
        bytes memory s = new bytes(len);
        for (uint256 i = 0; i < len; i++) s[i] = b[i];
        return string(s);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /// @inheritdoc IPTBridge
    function estimateBridgeCost(
        address pt,
        uint256 amount,
        string calldata stellarRecipient
    ) external view returns (uint256 gasCost) {
        if (address(messenger) == address(0)) return 0;

        IPrincipalToken ptToken = IPrincipalToken(pt);
        bytes memory payload = BridgeMessages.encodeBridgeToStellar(
            BridgeMessages.BridgeToStellarMsg({
                msgType: BridgeMessages.MSG_TYPE_BRIDGE_TO_STELLAR,
                ptAddress: pt,
                amount: amount,
                sourceChainId: uint32(block.chainid),
                stellarRecipient: stellarRecipient,
                maturity: ptToken.maturity(),
                underlying: ptToken.underlying(),
                decimals: ptToken.decimals(),
                ptSymbol: ptToken.symbol()
            })
        );

        return messenger.estimateGasCost(stellarChain, trustedRemote, payload);
    }

    function calculateBridgeFee(uint256 amount) external view returns (uint256 feeAmount, uint256 netAmount) {
        return _calculateFee(amount, bridgeFeeBps);
    }

    function calculateBridgeBackFee(uint256 amount) external view returns (uint256 feeAmount, uint256 netAmount) {
        return _calculateFee(amount, bridgeBackFeeBps);
    }

    function _calculateFee(uint256 amount, uint256 feeBps) internal pure returns (uint256 feeAmount, uint256 netAmount) {
        if (feeBps == 0) return (0, amount);
        feeAmount = (amount * feeBps) / BPS_DENOMINATOR;
        netAmount = amount - feeAmount;
    }

    function getRateLimitStatus(address pt) external view returns (
        int128 limit, int128 used, uint256 windowEnd
    ) {
        // Unset PT: behave as no-limit (matches Stellar's i128::MAX default).
        if (!rateLimitSet[pt]) return (type(int128).max, 0, 0);

        limit = rateLimitPerWindow[pt];
        // No-limit sentinel: skip window accounting, surface only the limit.
        if (limit == type(int128).max) return (limit, 0, 0);

        uint256 windowStart = _windowStart[pt];
        if (block.timestamp >= windowStart + rateLimitWindow) {
            return (limit, 0, block.timestamp + rateLimitWindow);
        }

        used = _windowVolume[pt];
        windowEnd = windowStart + rateLimitWindow;
    }

    /// @inheritdoc IPTBridge
    function lockedBalance(address pt) external view returns (uint256) {
        return _lockedBalances[pt];
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /// @inheritdoc IPTBridge
    function migrateMessenger(address newMessenger, string calldata newRemote) external restricted {
        _previous.messenger = messenger;
        _previous.trustedRemote = trustedRemote;
        trustedRemote = newRemote;
        emit MessengerMigrated(address(messenger), newMessenger, newRemote);
        messenger = IBridgeMessenger(newMessenger);
    }

    /// @notice Clears the previous messenger snapshot after in-flight messages
    ///         from the prior messenger have drained.
    function clearPreviousMessenger() external restricted {
        _previous.messenger = IBridgeMessenger(address(0));
        delete _previous.trustedRemote;
    }

    /// @inheritdoc IPTBridge
    function previousMessenger() external view returns (address) {
        return address(_previous.messenger);
    }

    /// @inheritdoc IPTBridge
    function previousTrustedRemote() external view returns (string memory) {
        return _previous.trustedRemote;
    }

    /// @inheritdoc IPTBridge
    function setStellarChain(string calldata stellarChain_) external restricted {
        if (bytes(stellarChain_).length == 0) revert EmptyStellarChain();
        emit StellarChainUpdated(stellarChain, stellarChain_);
        stellarChain = stellarChain_;
    }

    function setTrustedRemote(string calldata remoteAddress) external restricted {
        trustedRemote = remoteAddress;
    }

    function setBridgeFee(uint256 newFeeBps) external restricted {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        emit BridgeFeeUpdated(bridgeFeeBps, newFeeBps);
        bridgeFeeBps = newFeeBps;
    }

    function setFeeRecipient(address newFeeRecipient) external restricted {
        if (newFeeRecipient == address(0)) revert FeeRecipientNotSet();
        emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);
        feeRecipient = newFeeRecipient;
    }

    function setBridgeBackFee(uint256 newFeeBps) external restricted {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        emit BridgeBackFeeUpdated(bridgeBackFeeBps, newFeeBps);
        bridgeBackFeeBps = newFeeBps;
    }

    /// @notice Sets the rate limit for a PT.
    /// @dev Symmetric with Stellar:
    ///        unset            -> no limit (matches Stellar's i128::MAX default)
    ///        0                -> blocks bridging for this PT
    ///        type(int128).max -> no limit
    ///        0 < v < max      -> max signed volume per window
    function setRateLimit(address pt, int128 limitPerWindow) external restricted {
        require(limitPerWindow >= 0, "Limit must be non-negative");
        rateLimitPerWindow[pt] = limitPerWindow;
        rateLimitSet[pt] = true;
        emit RateLimitUpdated(pt, limitPerWindow, rateLimitWindow);
    }

    function setRateLimitWindow(uint256 windowSeconds) external restricted {
        require(windowSeconds > 0, "Zero window");
        rateLimitWindow = windowSeconds;
    }

    /// @inheritdoc IPTBridge
    function setWrappedPtBeacon(address beacon_) external restricted {
        require(beacon_ != address(0), "Zero address");
        emit WrappedPtBeaconUpdated(wrappedPtBeacon, beacon_);
        wrappedPtBeacon = beacon_;
    }

    function withdrawFees(address pt) external restricted {
        if (feeRecipient == address(0)) revert FeeRecipientNotSet();
        uint256 amount = feesCollected[pt];
        if (amount == 0) return;
        feesCollected[pt] = 0;
        IERC20(pt).safeTransfer(feeRecipient, amount);
        emit FeesWithdrawn(pt, feeRecipient, amount);
    }

    function pause() external restricted { _pause(); }
    function unpause() external restricted { _unpause(); }

}
