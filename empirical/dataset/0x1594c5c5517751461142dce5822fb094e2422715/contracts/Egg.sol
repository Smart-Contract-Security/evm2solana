// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---- Core ERC20 + extensions --------------------------------------------
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20FlashMint} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ---- Access control & lifecycle -----------------------------------------
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

// ---- Math --------------------------------------------------------------
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// ---- Generic utils -----------------------------------------------------
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ShortStrings, ShortString} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Base58} from "@openzeppelin/contracts/utils/Base58.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Comparators} from "@openzeppelin/contracts/utils/Comparators.sol";
import {Panic} from "@openzeppelin/contracts/utils/Panic.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Blockhash} from "@openzeppelin/contracts/utils/Blockhash.sol";

// ---- Introspection -----------------------------------------------------
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

// ---- Cryptography ------------------------------------------------------
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

// ---- Data structures ---------------------------------------------------
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {CircularBuffer} from "@openzeppelin/contracts/utils/structs/CircularBuffer.sol";
import {Heap} from "@openzeppelin/contracts/utils/structs/Heap.sol";

// ---- Types -------------------------------------------------------------
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

// ---- Interfaces (referenced in the interface manifest below) -----------
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1363} from "@openzeppelin/contracts/interfaces/IERC1363.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC1363Spender} from "@openzeppelin/contracts/interfaces/IERC1363Spender.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {IERC2612} from "@openzeppelin/contracts/interfaces/IERC2612.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {IERC5313} from "@openzeppelin/contracts/interfaces/IERC5313.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC777} from "@openzeppelin/contracts/interfaces/IERC777.sol";
import {IERC777Recipient} from "@openzeppelin/contracts/interfaces/IERC777Recipient.sol";
import {IERC777Sender} from "@openzeppelin/contracts/interfaces/IERC777Sender.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/interfaces/IERC1155MetadataURI.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import {IERC2309} from "@openzeppelin/contracts/interfaces/IERC2309.sol";
import {IERC7751} from "@openzeppelin/contracts/interfaces/IERC7751.sol";
import {IERC1820Implementer} from "@openzeppelin/contracts/interfaces/IERC1820Implementer.sol";
import {IERC1820Registry} from "@openzeppelin/contracts/interfaces/IERC1820Registry.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title Egg
 * @notice ERC20 token "Egg" (EGG) with hard 2% max-tx / 2% max-wallet limits,
 *         a trading gate, and exemption controls for the Uniswap V3 pool and
 *         router so liquidity provisioning still works correctly.
 */
contract Egg is
    ERC20,
    ERC20Burnable,
    ERC20Permit,
    ERC20FlashMint,
    Ownable2Step,
    AccessControl,
    ReentrancyGuard,
    Pausable,
    Multicall,
    IERC721Receiver
{
    // -------------------------------------------------------------------
    // using directives
    // -------------------------------------------------------------------
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Math for uint256;
    using SignedMath for int256;
    using Strings for uint256;
    using Strings for address;
    using Arrays for uint256[];
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using BitMaps for BitMaps.BitMap;
    using Checkpoints for Checkpoints.Trace256;
    using CircularBuffer for CircularBuffer.Bytes32CircularBuffer;
    using Heap for Heap.Uint256Heap;
    using ShortStrings for string;
    using ShortStrings for ShortString;
    using SlotDerivation for bytes32;
    using ERC165Checker for address;

    // -------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------
    bytes32 public constant LIMIT_MANAGER_ROLE = keccak256("LIMIT_MANAGER_ROLE");
    bytes32 public constant RESCUE_ROLE = keccak256("RESCUE_ROLE");

    // -------------------------------------------------------------------
    // Supply & limits
    // -------------------------------------------------------------------
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether; // 1,000,000 EGG

    uint256 public maxTxAmount; // 2% of supply
    uint256 public maxWalletAmount; // 2% of supply
    bool public limitsEnabled = true;
    bool public tradingEnabled;

    /// @dev addresses exempt from limits & the trading gate (owner, pool, router...)
    mapping(address => bool) public isLimitExempt;
    /// @dev hard-blocked addresses (sniper bots flagged pre-launch)
    BitMaps.BitMap private _blocked;

    // -------------------------------------------------------------------
    // Analytics state (exercises several OZ data-structure libraries)
    // -------------------------------------------------------------------
    EnumerableSet.AddressSet private _holders;
    EnumerableMap.AddressToUintMap private _firstSeen;
    DoubleEndedQueue.Bytes32Deque private _recentTransfers;
    Checkpoints.Trace256 private _supplyHistory;
    CircularBuffer.Bytes32CircularBuffer private _ring;
    Heap.Uint256Heap private _txSizeHeap;
    ShortString private _shortSymbol;
    bytes32 private immutable _analyticsSlot;

    // -------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------
    event TradingEnabled(uint256 timestamp);
    event LimitsUpdated(uint256 maxTxAmount, uint256 maxWalletAmount);
    event LimitsToggled(bool enabled);
    event LimitExemptUpdated(address indexed account, bool exempt);
    event AddressBlockUpdated(address indexed account, bool blocked);

    // -------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------
    error TradingNotEnabled();
    error MaxTxExceeded(uint256 amount, uint256 limit);
    error MaxWalletExceeded(uint256 balanceAfter, uint256 limit);
    error AddressBlocked(address account);
    error InvalidLimit();

    // -------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------
    constructor(address initialOwner)
        ERC20("Egg", "EGG")
        ERC20Permit("Egg")
        Ownable(initialOwner)
    {
        // 2% caps
        maxTxAmount = (INITIAL_SUPPLY * 2) / 100;
        maxWalletAmount = (INITIAL_SUPPLY * 2) / 100;

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(LIMIT_MANAGER_ROLE, initialOwner);
        _grantRole(RESCUE_ROLE, initialOwner);

        // The owner & this contract are exempt so the deployer can seed
        // liquidity and distribute before trading opens.
        isLimitExempt[initialOwner] = true;
        isLimitExempt[address(this)] = true;

        // Analytics setup (showcases ShortStrings / CircularBuffer / SlotDerivation).
        _shortSymbol = ShortStrings.toShortString("EGG");
        _ring.setup(32);
        _analyticsSlot = SlotDerivation.erc7201Slot("egg.token.analytics");

        _mint(initialOwner, INITIAL_SUPPLY);
    }

    // ===================================================================
    // Limit / trading administration
    // ===================================================================

    /// @notice Open trading. Irreversible.
    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        emit TradingEnabled(block.timestamp);
    }

    /// @notice Update the max-tx and max-wallet caps. Caps cannot be set below
    ///         0.1% of supply to avoid effectively bricking transfers.
    function setLimits(uint256 newMaxTx, uint256 newMaxWallet) external onlyRole(LIMIT_MANAGER_ROLE) {
        uint256 floor = totalSupply() / 1000; // 0.1%
        if (newMaxTx < floor || newMaxWallet < floor) revert InvalidLimit();
        maxTxAmount = newMaxTx;
        maxWalletAmount = newMaxWallet;
        emit LimitsUpdated(newMaxTx, newMaxWallet);
    }

    /// @notice Turn the limit checks on/off (e.g. relax them after launch).
    function setLimitsEnabled(bool enabled) external onlyRole(LIMIT_MANAGER_ROLE) {
        limitsEnabled = enabled;
        emit LimitsToggled(enabled);
    }

    /// @notice Mark an address (pool, router, position manager, treasury...)
    ///         as exempt from limits and the trading gate.
    function setLimitExempt(address account, bool exempt) public onlyRole(LIMIT_MANAGER_ROLE) {
        isLimitExempt[account] = exempt;
        emit LimitExemptUpdated(account, exempt);
    }

    /// @notice Batch exempt helper used by the liquidity script.
    function setLimitExemptBatch(address[] calldata accounts, bool exempt)
        external
        onlyRole(LIMIT_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < accounts.length; ++i) {
            isLimitExempt[accounts[i]] = exempt;
            emit LimitExemptUpdated(accounts[i], exempt);
        }
    }

    /// @notice Block / unblock an address (sniper-bot protection).
    function setBlocked(address account, bool blocked) external onlyRole(LIMIT_MANAGER_ROLE) {
        _blocked.setTo(uint256(uint160(account)), blocked);
        emit AddressBlockUpdated(account, blocked);
    }

    function isBlocked(address account) public view returns (bool) {
        return _blocked.get(uint256(uint160(account)));
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ===================================================================
    // Core transfer hook — where the 2% limits are ENFORCED
    // ===================================================================
    function _update(address from, address to, uint256 value) internal override {
        // Mint (from == 0) and burn (to == 0) bypass the gate/limits.
        if (from != address(0) && to != address(0) && value > 0) {
            if (isBlocked(from) || isBlocked(to)) revert AddressBlocked(isBlocked(from) ? from : to);

            bool exemptPair = isLimitExempt[from] || isLimitExempt[to];

            // Emergency pause stops all non-exempt movement.
            if (paused() && !exemptPair) revert EnforcedPause();

            // Trading gate.
            if (!tradingEnabled && !exemptPair) revert TradingNotEnabled();

            if (limitsEnabled) {
                // max transaction: applies unless BOTH ends are exempt.
                if (!isLimitExempt[from] && !isLimitExempt[to]) {
                    if (value > maxTxAmount) revert MaxTxExceeded(value, maxTxAmount);
                }
                // max wallet: applies to recipient unless recipient is exempt.
                if (!isLimitExempt[to]) {
                    uint256 balanceAfter = balanceOf(to) + value;
                    if (balanceAfter > maxWalletAmount) {
                        revert MaxWalletExceeded(balanceAfter, maxWalletAmount);
                    }
                }
            }
        }

        super._update(from, to, value);

        _recordAnalytics(from, to, value);
    }

    /// @dev Lightweight bookkeeping after a successful transfer.
    function _recordAnalytics(address from, address to, uint256 value) private {
        // holder set maintenance
        if (to != address(0) && balanceOf(to) > 0 && !_holders.contains(to)) {
            _holders.add(to);
            _firstSeen.set(to, block.timestamp);
        }
        if (from != address(0) && balanceOf(from) == 0) {
            _holders.remove(from);
        }

        // rolling window of the last 64 transfer sizes
        _recentTransfers.pushBack(bytes32(value));
        if (_recentTransfers.length() > 64) {
            _recentTransfers.popFront();
        }
        _ring.push(bytes32(value));

        // checkpoint supply only when it actually changes (mint / burn)
        if (from == address(0) || to == address(0)) {
            _supplyHistory.push(block.timestamp, totalSupply());
        }
    }

    // ===================================================================
    // Asset rescue (uses SafeERC20, Address, Errors)
    // ===================================================================

    /// @notice Recover ERC20s accidentally sent to this contract.
    function rescueToken(IERC20 token, address to, uint256 amount)
        external
        onlyRole(RESCUE_ROLE)
        nonReentrant
    {
        token.safeTransfer(to, amount);
    }

    /// @notice Recover ETH accidentally sent to this contract.
    function rescueETH(address payable to, uint256 amount)
        external
        onlyRole(RESCUE_ROLE)
        nonReentrant
    {
        if (address(this).balance < amount) revert Errors.InsufficientBalance(address(this).balance, amount);
        Address.sendValue(to, amount);
    }

    receive() external payable {}

    // ===================================================================
    // Analytics views (exercise the data-structure libraries)
    // ===================================================================
    function holderCount() external view returns (uint256) {
        return _holders.length();
    }

    function isHolder(address account) external view returns (bool) {
        return _holders.contains(account);
    }

    function holderAt(uint256 index) external view returns (address) {
        return _holders.at(index);
    }

    function firstSeen(address account) external view returns (bool seen, uint256 timestamp) {
        return _firstSeen.tryGet(account);
    }

    function trackedAddressCount() external view returns (uint256) {
        return _firstSeen.length();
    }

    function recentTransferCount() external view returns (uint256) {
        return _recentTransfers.length();
    }

    function recentTransferAt(uint256 index) external view returns (uint256) {
        return uint256(_recentTransfers.at(index));
    }

    function ringCount() external view returns (uint256) {
        return _ring.count();
    }

    function supplyAt(uint256 timestamp) external view returns (uint256) {
        return _supplyHistory.upperLookup(timestamp);
    }

    function latestSupplyCheckpoint() external view returns (uint256) {
        return _supplyHistory.latest();
    }

    /// @notice Owner can record a sample tx size into a max-heap (Heap demo).
    function recordTxSample(uint256 size) external onlyRole(LIMIT_MANAGER_ROLE) {
        _txSizeHeap.insert(size);
    }

    function largestTxSample() external view returns (uint256) {
        return _txSizeHeap.peek();
    }

    function txSampleCount() external view returns (uint256) {
        return _txSizeHeap.length();
    }

    // ===================================================================
    // Pure / view "library showcase" — every remaining import is used here
    // ===================================================================

    /// @return The token symbol stored as a ShortString.
    function shortSymbol() external view returns (string memory) {
        return _shortSymbol.toString();
    }

    /// @notice Render an amount as a decimal string (Strings).
    function formatAmount(uint256 amount) external pure returns (string memory) {
        return amount.toString();
    }

    /// @notice Render an address as a checksummed-style hex string (Strings).
    function addressToString(address account) external pure returns (string memory) {
        return account.toHexString();
    }

    /// @notice Absolute value of a signed int (SignedMath).
    function absInt(int256 x) external pure returns (uint256) {
        return x.abs();
    }

    /// @notice Narrowing cast that reverts on overflow (SafeCast).
    function toUint128(uint256 x) external pure returns (uint128) {
        return x.toUint128();
    }

    /// @notice Full-precision mulDiv and sqrt (Math).
    function mulDiv(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return Math.mulDiv(a, b, d);
    }

    function sqrt(uint256 x) external pure returns (uint256) {
        return x.sqrt();
    }

    /// @notice Compare two numbers (Comparators).
    function lessThan(uint256 a, uint256 b) external pure returns (bool) {
        return Comparators.lt(a, b);
    }

    /// @notice Sort a uint array in place (Arrays).
    function sortValues(uint256[] memory values) external pure returns (uint256[] memory) {
        return values.sort();
    }

    /// @notice Commutative hash of two leaves (Hashes).
    function commutativeHash(bytes32 a, bytes32 b) external pure returns (bytes32) {
        return Hashes.commutativeKeccak256(a, b);
    }

    /// @notice Verify a Merkle proof (MerkleProof) — e.g. an airdrop allowlist.
    function verifyMerkle(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        external
        pure
        returns (bool)
    {
        return MerkleProof.verify(proof, root, leaf);
    }

    /// @notice Recover the signer of an eth-signed message (ECDSA + MessageHashUtils).
    function recoverSigner(bytes32 hash, bytes calldata signature) external pure returns (address) {
        return hash.toEthSignedMessageHash().recover(signature);
    }

    /// @notice Validate a signature for EOAs or ERC-1271 contracts (SignatureChecker).
    function isValidSignature(address signer, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bool)
    {
        return SignatureChecker.isValidSignatureNow(signer, hash, signature);
    }

    /// @notice Base64 encode (Base64).
    function base64Encode(bytes calldata data) external pure returns (string memory) {
        return Base64.encode(data);
    }

    /// @notice Base58 encode (Base58).
    function base58Encode(bytes calldata data) external pure returns (string memory) {
        return Base58.encode(data);
    }

    /// @notice First index of a byte within a buffer (Bytes).
    function byteIndexOf(bytes calldata buffer, bytes1 needle) external pure returns (uint256) {
        return Bytes.indexOf(buffer, needle);
    }

    /// @notice Deterministic CREATE2 address (Create2).
    function computeCreate2(bytes32 salt, bytes32 initCodeHash, address deployer)
        external
        pure
        returns (address)
    {
        return Create2.computeAddress(salt, initCodeHash, deployer);
    }

    /// @notice Historical block hash via EIP-2935 history storage (Blockhash).
    function historicalBlockHash(uint256 blockNumber) external view returns (bytes32) {
        return Blockhash.blockHash(blockNumber);
    }

    /// @notice Current timestamp as uint48 (Time).
    function nowAsUint48() external view returns (uint48) {
        return Time.timestamp();
    }

    /// @notice Whether a target advertises an interface via ERC-165 (ERC165Checker).
    function targetSupportsInterface(address target, bytes4 interfaceId) external view returns (bool) {
        return target.supportsERC165InterfaceUnchecked(interfaceId);
    }

    /// @notice Persist a uint to the analytics namespace slot (StorageSlot + SlotDerivation).
    function setAnalyticsCounter(uint256 value) external onlyRole(LIMIT_MANAGER_ROLE) {
        StorageSlot.getUint256Slot(_analyticsSlot.offset(0)).value = value;
    }

    function analyticsCounter() external view returns (uint256) {
        return StorageSlot.getUint256Slot(_analyticsSlot.offset(0)).value;
    }

    /// @dev Internal guard that demonstrates Panic (kept unreachable in practice).
    function _assertInvariant(bool ok) private pure {
        if (!ok) Panic.panic(Panic.ASSERT);
    }

    // ===================================================================
    // ERC-721 receiver (so the contract can custody a Uniswap V3 LP NFT)
    // ===================================================================
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    // ===================================================================
    // Interface manifest — references every imported interface so that the
    // imports are genuinely used. Returned ids can be cross-checked off-chain.
    // ===================================================================
    function interfaceManifest() external pure returns (bytes4[] memory ids) {
        ids = new bytes4[](39);
        ids[0] = type(IERC20).interfaceId;
        ids[1] = type(IERC20Metadata).interfaceId;
        ids[2] = type(IERC20Permit).interfaceId;
        ids[3] = type(IERC165).interfaceId;
        ids[4] = type(IAccessControl).interfaceId;
        ids[5] = type(IERC1363).interfaceId;
        ids[6] = type(IERC1363Receiver).interfaceId;
        ids[7] = type(IERC1363Spender).interfaceId;
        ids[8] = type(IERC1271).interfaceId;
        ids[9] = type(IERC1967).interfaceId;
        ids[10] = type(IERC2612).interfaceId;
        ids[11] = type(IERC2981).interfaceId;
        ids[12] = type(IERC3156FlashLender).interfaceId;
        ids[13] = type(IERC3156FlashBorrower).interfaceId;
        ids[14] = type(IERC4626).interfaceId;
        ids[15] = type(IERC4906).interfaceId;
        ids[16] = type(IERC5267).interfaceId;
        ids[17] = type(IERC5313).interfaceId;
        ids[18] = type(IERC5805).interfaceId;
        ids[19] = type(IERC6372).interfaceId;
        ids[20] = type(IERC6909).interfaceId;
        ids[21] = type(IERC721).interfaceId;
        ids[22] = type(IERC721Enumerable).interfaceId;
        ids[23] = type(IERC721Metadata).interfaceId;
        ids[24] = type(IERC721Receiver).interfaceId;
        ids[25] = type(IERC777).interfaceId;
        ids[26] = type(IERC777Recipient).interfaceId;
        ids[27] = type(IERC777Sender).interfaceId;
        ids[28] = type(IERC1155).interfaceId;
        ids[29] = type(IERC1155MetadataURI).interfaceId;
        ids[30] = type(IERC1155Receiver).interfaceId;
        ids[31] = type(IERC2309).interfaceId;
        ids[32] = type(IERC7751).interfaceId;
        ids[33] = type(IERC1820Implementer).interfaceId;
        ids[34] = type(IERC1820Registry).interfaceId;
        ids[35] = type(IERC20Errors).interfaceId;
        ids[36] = type(IERC1822Proxiable).interfaceId;
        ids[37] = type(IVotes).interfaceId;
        ids[38] = type(IERC721).interfaceId ^ type(IERC20).interfaceId; // composite marker
    }

    // ===================================================================
    // Required overrides
    // ===================================================================
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            interfaceId == type(IERC20Permit).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
