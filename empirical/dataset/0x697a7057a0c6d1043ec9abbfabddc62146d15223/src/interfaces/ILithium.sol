// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @title ILithium
/// @notice Interface for the Lithium payment channel contract.
///         Lithium enables two participants to open a channel, deposit funds, and conduct off-chain payments.
///         Settlements can occur on-chain cooperatively or unilaterally, with support for multiple assets.
/// @dev All functions are external; implementations delegate to libraries for core logic.
///
///      The contract is permissionless at the EVM level, but the protocol's security and liveness
///      guarantees apply only to states co-signed under an off-chain implementation that validates
///      protocol-critical preconditions before signing. Any implementation that co-signs states for
///      this contract MUST reject unsupported configurations, including incompatible assets,
///      unsafe dispute periods, excessive pending-payment sets, and counterparties or recipient
///      addresses that cannot receive the assets involved in cooperative wallet-directed
///      withdrawals or direct caller payouts. States co-signed without these checks are outside
///      the supported security model.
///
///      The protocol is permissionless: it accepts any ERC-standard token without whitelists.
///      Security relies on channel isolation, mutual co-signature requirements, reentrancy guards
///      (OpenZeppelin ReentrancyGuardTransient on every external function), and CEI ordering — not
///      on restricting which assets can be used. Fee-on-transfer and rebasing tokens are incompatible
///      and not supported; preventing their use is an off-chain signing responsibility (see README).
///
///      Hashlock payment (HTLC) arrays are unbounded on-chain. The off-chain implementation MUST enforce a
///      practical cap (50–100 per asset per state) to bound Merkle-tree computation, calldata cost,
///      and settlement gas. See LithiumVerification.calculateMerkleRootAndVerifyPreimages.
///
///      Adversarial settlement and revocation use deterministic delivery rules to avoid griefing:
///      the beneficiary who is also `msg.sender` is paid directly, while all other payouts are
///      moved into `Storage.claimable` for later withdrawal via `claimAsset`. This prevents one
///      participant's receive behavior from blocking finalization. Cooperative withdrawals
///      (`withdrawFromPool`, `processBalanceChanges`) still revert on transfer failure.
///
///      All signed payloads use `abi.encodePacked` with exclusively fixed-size types (address,
///      uint256, enum, bytes32). Combined with domain separation (`address(this)`, `block.chainid`)
///      and monotonic counters (`nonce`, `onchainNonce`), there is no practical collision or
///      replay risk. See LithiumVerification for details.
interface ILithium {
    /// @notice Emitted when multiple assets are distributed during settlement (e.g., revoke or confirm).
    /// @param assetDistributions Array of asset distribution details for each settled asset.
    event AssetsDistributed(AssetDistribution[] assetDistributions);

    /// @notice Batch aggregation for multiple asset channel updates in a single transaction.
    ///         Each AssetState is signed individually by both parties.
    ///         Allows deposits, withdrawals, and balance reallocations.
    /// @param channelConfig The channel configuration (e.g., participants, dispute period).
    /// @param assetStates Array of new asset states (one per asset).
    function updateChannel(ChannelConfig calldata channelConfig, SignedAssetState[] calldata assetStates)
        external
        payable;

    /// @notice Unilaterally settle the channel by providing the latest states and signatures.
    ///         Pending hashlock payments require preimages; unknown preimages set to bytes32(0).
    /// @param channelConfig The channel configuration.
    /// @param assetStates Array of asset states.
    /// @param hashlockPaymentsArray Arrays of pending hashlock payments for each asset state.
    function unilateralSettleChannel(
        ChannelConfig calldata channelConfig,
        SignedAssetState[] calldata assetStates,
        HashlockPayment[][] calldata hashlockPaymentsArray
    ) external;

    /// @notice Confirm unilateral settlements for multiple assets after the dispute period.
    /// @param alice Alice's address in the disputed channel.
    /// @param bob Bob's address in the disputed channel.
    /// @param channelNumber The channel number.
    /// @param assetVariants Array of asset variants.
    /// @param assetAddresses Array of asset addresses.
    /// @param tokenNumberIds Array of token IDs (for NFTs; 0 for fungibles).
    function confirmUnilateralSettlement(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant[] calldata assetVariants,
        address[] calldata assetAddresses,
        uint256[] calldata tokenNumberIds
    ) external;

    /// @notice Penalize a participant that broadcasted a revoked channel state.
    ///         Two paths: (1) dispute path — cumulative revocations only (balanceSum == 0),
    ///         penalizes a revoker who opened a unilateral settlement with a revoked nonce;
    ///         (2) cooperative path — nonce-specific revocations only (balanceSum > 0),
    ///         penalizes a revoker who broadcast a revoked state via updateChannel.
    ///         Revocations are signed unilaterally by the revoking party.
    ///         All funds are sent to the non-revoking party (the victim). The function is
    ///         permissionless: any caller can invoke it, but the reward recipient is deterministic
    ///         (always the victim), making front-running unprofitable.
    /// @param alice Alice's address in the channel.
    /// @param bob Bob's address in the channel.
    /// @param channelNumber The channel number.
    /// @param revocations Array of revocation details (one per asset).
    function penalizeRevokedChannel(
        address alice,
        address bob,
        uint256 channelNumber,
        SignedRevocation[] calldata revocations
    ) external;

    /// @notice Deposit an asset into the liquidity pool.
    /// @param assetVariant The variant of the asset (e.g., Native for ETH).
    /// @param assetAddress The address of the asset (0 for Native).
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    /// @param amount Amount of the asset to deposit (msg.value for Native).
    function depositToPool(AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId, uint256 amount)
        external
        payable;

    /// @notice Withdraw an asset from the liquidity pool.
    /// @param assetVariant The variant of the asset.
    /// @param assetAddress The address of the asset.
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    /// @param amount Amount of the asset to withdraw.
    function withdrawFromPool(AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId, uint256 amount)
        external;

    /// @notice Execute a batch of operations in a single transaction to save gas.
    /// @param ops Array of batch operations (e.g., updates, settlements).
    function batchExecute(BatchOp[] calldata ops) external payable;

    /// @notice Retrieve the liquidity amounts for a provider across multiple assets.
    /// @param provider The liquidity provider's address.
    /// @param assetVariant The asset variant to query.
    /// @param assetAddress The asset address to query.
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    /// @return liquidity The liquidity amount for the specified asset.
    function getLiquidity(address provider, AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId)
        external
        view
        returns (uint256 liquidity);

    /// @notice Retrieve the dispute state for a specific asset in a channel.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param assetVariant The asset variant.
    /// @param assetAddress The asset address.
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    /// @return dispute The dispute details (e.g., nonce, deadline, balances).
    function getAssetDispute(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId
    ) external view returns (Dispute memory dispute);

    /// @notice Returns the packed state hash for a specific asset channel.
    /// @param alice Alice's address.
    /// @param bob Bob's address.
    /// @param channelNumber The channel number.
    /// @param assetVariant The asset variant.
    /// @param assetAddress The asset contract address (address(0) for native).
    /// @param tokenNumberId The token ID (0 for fungibles).
    /// @return assetChannel The packed keccak256 state hash (nonce, balanceSum, lastUpdater).
    ///         Returns bytes32(0) if the channel has never been opened, or CLOSED_CHANNEL_SENTINEL
    ///         if the channel was adversarially closed.
    function getAssetChannel(
        address alice,
        address bob,
        uint256 channelNumber,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId
    ) external view returns (bytes32 assetChannel);

    /// @notice Claim escrowed assets assigned during adversarial settlement or revocation.
    /// @dev Pull-payment fallback for deterministic escrow paths. The recipient can later call
    ///      this function to withdraw their escrowed funds.
    /// @param assetVariant The variant of the asset to claim.
    /// @param assetAddress The address of the asset contract (address(0) for Native).
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    function claimAsset(AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId) external;

    /// @notice Returns the escrowed (claimable) amount for a user and asset.
    /// @param user The user's address.
    /// @param assetVariant The asset variant.
    /// @param assetAddress The asset contract address.
    /// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
    /// @return amount The claimable amount.
    function getClaimable(address user, AssetVariant assetVariant, address assetAddress, uint256 tokenNumberId)
        external
        view
        returns (uint256 amount);

    /// @notice Receive function to deposit ETH into the liquidity pool.
    /// @dev Uses msg.value as the deposit amount for Native asset.
    receive() external payable;
}

/// @notice Global storage struct for the contract.
/// @dev Uses mappings with keccak256 keys for efficient storage.
struct Storage {
    // keccak(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId) => keccak(nonce, balanceSum, msg.sender)
    mapping(bytes32 => bytes32) assetChannels;
    // keccak(alice, bob, channelNumber, assetVariant, assetAddress, tokenNumberId) => Dispute
    mapping(bytes32 => Dispute) assetDisputes;
    // liquidity provider => keccak(assetVariant, assetAddress, tokenNumberId) => amount
    mapping(address => mapping(bytes32 => uint256)) liquidityPool;
    // user => keccak(assetVariant, assetAddress, tokenNumberId) => escrowed amount (pull-payment fallback)
    mapping(address => mapping(bytes32 => uint256)) claimable;
}

/// @notice Enum for batch operation types.
/// @dev Used in batchExecute to specify the operation.
enum OpType {
    UpdateChannel,
    UnilateralSettleChannel,
    ConfirmUnilateralSettlement,
    PenalizeRevokedChannel,
    DepositToPool,
    WithdrawFromPool,
    ClaimAsset
}

/// @notice Struct for batch operations.
/// @dev Encodes the operation type and ABI-encoded data.
struct BatchOp {
    OpType opType;
    bytes data;
}

/// @notice Configuration for a payment channel.
/// @dev Defines the channel participants and rules.
///      `disputePeriod` is uint64 for consistency with the Dispute struct's `disputeDeadline`
///      (both represent timestamps/durations in seconds). uint64 is safe until year ~584 billion.
///      **Off-chain requirement**: The off-chain implementation MUST enforce `disputePeriod > 0` before
///      co-signing any state. A zero dispute period allows atomic stale-state settlement via
///      `batchExecute` (unilateralSettle + confirmSettlement in one tx), giving the counterparty
///      zero time to challenge. The contract does not enforce a minimum on-chain because the
///      appropriate minimum depends on chain finality and off-chain monitoring latency. The
///      on-chain contract does enforce that `block.timestamp + disputePeriod` does not overflow
///      `uint64` (reverts with `InvalidDisputePeriod` if it does).
/// @param alice Alice's address.
/// @param bob Bob's address.
/// @param channelNumber Unique channel identifier.
/// @param disputePeriod Dispute resolution period in seconds. MUST be > 0 (enforced off-chain).
struct ChannelConfig {
    address alice;
    address bob;
    uint256 channelNumber;
    uint64 disputePeriod; // in seconds
}

/// @notice Enum for supported asset types.
/// @dev Determines how assets are transferred (e.g., Native for ETH).
enum AssetVariant {
    Native, // e.g., ETH
    ERC20,
    ERC721,
    ERC1155,
    ERC6909
}

/// @notice State of an asset within a channel.
/// @dev Tracks balances, nonces, and pending payments for an asset.
///      For ERC721 assets, the sum `balances.alice + balances.bob` should be 0 or 1.
///      This is enforced off-chain by the co-signature requirement — both parties must agree on
///      every state. The transfer layer enforces `amount == 1` per ERC721 operation in
///      `withdrawAssetTo`, so invalid co-signed states fail at settlement execution.
///      Off-chain implementations MUST co-sign states only if both participants can safely receive
///      the asset in all payout paths that the state may trigger on-chain. Recipient compatibility
///      is protocol-critical because unilateral settlement and revocation transfer assets directly
///      to participants' addresses.
///      Off-chain implementations MUST also durably persist the latest co-signed states,
///      revocations, and settlement-critical challenge data before treating a transition as
///      accepted, because the contract cannot reconstruct data that a participant loses.
/// @param withdrawSetting Specifies withdrawal destinations (wallet or pool).
/// @param assetVariant The asset type.
/// @param assetAddress The asset contract address.
/// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
/// @param nonce Current off-chain state version.
/// @param onchainNonce Previous on-chain state version.
/// @param balances Current balances for Alice and Bob.
/// @param previousBalances Previous balances for validation.
/// @param hashlockPaymentsMerkleRoot Merkle root of pending hashlock payments.
struct AssetState {
    WithdrawSetting withdrawSetting; // indicating if funds should be transfered to wallet or to liquidity pool
    AssetVariant assetVariant; // variant of the asset (Native, ERC20, ERC721, ERC1155, ERC6909)
    address assetAddress;
    uint256 tokenNumberId; // token ID for NFTs, 0 for fungible assets
    uint256 nonce; // version number of the last off-chain update of the AssetState
    uint256 onchainNonce; // version number of the last broadcasted on-chain AssetState
    AssetBalance balances;
    AssetBalance previousBalances;
    bytes32 hashlockPaymentsMerkleRoot;
}

/// @notice Struct of an asset state with signatures.
/// @dev Used in operations requiring signed states.
struct SignedAssetState {
    AssetState assetState;
    bytes aliceSignature;
    bytes bobSignature;
}

/// @notice Struct for revoking an asset state.
/// @dev Contains the asset identifiers and the nonce to revoke.
///      Two modes: cumulative revokes all states up to `nonce` (used after off-chain payments),
///      nonce-specific revokes only the exact `nonce` (used after on-chain deposits).
///      Signed unilaterally by the revoking party (not co-signed).
///      `balanceSum` is required for nonce-specific revocations targeting cooperative updates
///      (to verify the stored assetChannel hash); set to 0 for cumulative revocations.
/// @param assetVariant The asset type.
/// @param assetAddress The asset contract address.
/// @param tokenNumberId Token ID for NFTs; 0 for fungibles.
/// @param nonce For cumulative: all states ≤ nonce are revoked. For specific: only this nonce.
/// @param balanceSum Total balance (alice + bob) at the revoked nonce.
///        When > 0: nonce-specific revocation (eligible for cooperative-path verification via assetChannels).
///        When == 0: cumulative revocation (dispute-path only, covers all nonces ≤ `nonce`).
///        A zero-balance nonce-specific revocation is vacuous (no funds to penalize) so the
///        conflation with cumulative is harmless.
struct Revocation {
    AssetVariant assetVariant;
    address assetAddress;
    uint256 tokenNumberId; // token ID for NFTs, 0 for fungible assets
    uint256 nonce; // version number of the off-chain AssetState to be revoked
    uint256 balanceSum; // 0 = cumulative, > 0 = nonce-specific (cooperative-path eligible)
}

/// @notice Struct of a revocation with the revoker's signature.
/// @dev Used in penalizeRevokedChannel. Signed unilaterally by the revoking party.
///      The contract recovers the signer via ECDSA to identify the revoker (Alice or Bob).
struct SignedRevocation {
    Revocation revocation;
    bytes revokerSignature;
}

/// @notice Balances for Alice and Bob.
/// @dev Simple struct for participant balances.
/// @param alice Alice's balance.
/// @param bob Bob's balance.
struct AssetBalance {
    uint256 alice;
    uint256 bob;
}

/// @notice Details of a hashlock payment.
/// @dev Used for conditional payments (hash-time-locked contracts).
///      `resolutionDeadline` is uint64 (same rationale as `disputePeriod`): timestamps
///      fit comfortably within 2^64 seconds (~584 billion years), and the smaller type
///      lets `resolutionDeadline` + `direction` (1 byte) pack into a single 32-byte slot,
///      reducing storage from 5 to 4 slots per payment (~20 % gas saving on HTLC writes/clears).
/// @param amount Payment amount.
/// @param hash SHA256 hash of the preimage.
/// @param resolutionDeadline Timestamp for resolution (uint64, safe until ~year 584 B).
/// @param direction Direction of the payment.
/// @param preimage Preimage (0x0 if unknown).
struct HashlockPayment {
    uint256 amount;
    bytes32 hash; // sha256 hash of the payment preimage
    uint64 resolutionDeadline; // timestamp in seconds (packs with `direction` into one slot)
    PaymentDirection direction;
    bytes32 preimage; // payment preimage (0x0 if not known)
}

/// @notice Enum for payment directions.
/// @dev Specifies payer/payee in hashlock payments.
enum PaymentDirection {
    AliceToBob,
    BobToAlice
}

/// @notice Enum for withdrawal settings.
/// @dev Controls where settled funds are sent (wallet or liquidity pool).
enum WithdrawSetting {
    AliceToWalletBobToPool, // 0x0
    AliceToPoolBobToPool, // 0x1
    AliceToWalletBobToWallet, // 0x2
    AliceToPoolBobToWallet // 0x3
}

/// @notice Dispute details for an asset.
/// @dev Stored during unilateral settlements for challenge period.
///
///      Higher-nonce submissions override lower-nonce disputes without penalizing the previous
///      disputer. This separation prevents the withholding attack: Party B withholds the
///      co-signature for nonce N+1, leaving Party A with nonce N; if the dispute path penalized
///      stale nonces, Party A (the victim) would be punished. Fraud penalties are handled
///      exclusively by the revocation mechanism (`penalizeRevokedChannel`).
///
///      A co-signed state with a higher nonce represents a strictly more recent agreement that
///      must take precedence. Overwriting the dispute is necessary for protocol correctness —
///      the dispute must converge to the latest state.
///
///      Storage layout: `disputeDeadline` (uint64) and `disputerIsAlice` (bool) are packed into
///      a single 32-byte slot, saving one SSTORE/SLOAD per dispute lifecycle compared to storing
///      them in separate slots. uint64 timestamps are safe until year ~584 billion.
///      The disputer is always Alice or Bob (enforced by the `InvalidSender` guard on initial
///      disputes), so a boolean is sufficient.
///
///      **Off-chain requirement**: The off-chain implementation MUST limit the number of concurrent
///      `hashlockPayments` per asset channel. The `HashlockPayment[]` array is unbounded on-chain.
///      Each element occupies 5 storage slots; `delete store.assetDisputes[...]` during
///      `confirmUnilateralSettlement` or `penalizeRevokedChannel` performs O(N) SSTORE-to-zero
///      operations. With ≥500 payments, gas costs may exceed L2 block limits; with ≥1000, L1
///      limits. A practical cap (e.g., 50–100 payments, similar to Lightning's 483 HTLC limit)
///      must be enforced off-chain before co-signing any state.
///
///      **Off-chain requirement**: Because unilateral settlement confirmation and revocation send
///      assets directly to participant addresses, implementations MUST reject channel configurations
///      and state transitions involving counterparties that cannot reliably receive the relevant
///      asset standard. This includes native-asset recipients that revert on ETH, ERC721/ERC1155
///      recipients lacking the required receiver behavior, and any address whose transfer behavior
///      would make settlement or revocation non-finalizable.
/// @param nonce State nonce.
/// @param disputeDeadline Dispute resolution deadline (uint64, packed with disputerIsAlice).
/// @param disputerIsAlice True if Alice initiated the dispute, false if Bob.
/// @param balances Balances at dispute time.
/// @param hashlockPayments Array of hashlock payments.
/// @param hashlockPaymentsMerkleRoot Merkle root of hashlock payments.
struct Dispute {
    uint256 nonce; // version number of the last off-chain update of the AssetState
    uint64 disputeDeadline; // timestamp in seconds (packed with disputerIsAlice)
    bool disputerIsAlice; // true = Alice initiated the dispute, false = Bob
    AssetBalance balances;
    HashlockPayment[] hashlockPayments;
    bytes32 hashlockPaymentsMerkleRoot;
}

/// @notice Details of an asset distribution during settlement.
/// @dev Returned/emitted on settlements to detail fund transfers.
/// @param assetVariant Asset type.
/// @param assetAddress Asset contract address.
/// @param tokenNumberId Token ID.
/// @param aliceAmount Amount distributed to Alice.
/// @param bobAmount Amount distributed to Bob.
/// @param aliceRecipient Recipient of Alice's amount.
/// @param bobRecipient Recipient of Bob's amount.
struct AssetDistribution {
    AssetVariant assetVariant;
    address assetAddress;
    uint256 tokenNumberId; // token ID for NFTs, 0 for fungible assets
    uint256 aliceAmount;
    uint256 bobAmount;
    address aliceRecipient; // recipient of Alice's funds
    address bobRecipient; // recipient of Bob's funds
}

/// @notice Thrown when the submitted previous state hash doesn't match the stored on-chain hash.
error InvalidPreviousState();
/// @notice Thrown when msg.value doesn't match the required ETH amount.
error EthTxValueMismatch();
/// @notice Thrown when an ETH transfer via low-level call fails.
error EthTransferFailed();
/// @notice Thrown when an ERC721 operation uses an amount other than 1.
error InvalidERC721Amount();
/// @notice Thrown when an ERC6909 transferFrom returns false.
error ERC6909TransferFailed();
/// @notice Thrown for unrecognized AssetVariant enum values.
error UnknownTokenVariant();
/// @notice Thrown when msg.sender is not a channel participant (Alice or Bob).
error InvalidSender();
/// @notice Thrown when a submitted nonce violates monotonicity constraints.
error InvalidNonce();
/// @notice Thrown when the computed HTLC Merkle root doesn't match the signed state's root.
error InvalidMerkleRoot();
/// @notice Thrown when an asset state doesn't match the expected dispute values (same-nonce update or revocation).
error InvalidAssetState();
/// @notice Thrown when a same-nonce HTLC update is attempted but no payments exist in the dispute.
error NoNewPayments();
/// @notice Thrown when the HTLC array length doesn't match the dispute's stored array length.
error InvalidPaymentsLength();
/// @notice Thrown when a same-nonce HTLC update provides no new preimages.
error NoNewPreimages();
/// @notice Thrown when array lengths for multi-asset operations don't match.
error LengthMismatch();
/// @notice Thrown when attempting a cooperative update while a dispute is active.
error InDispute();
/// @notice Thrown when attempting to confirm settlement or penalize without an active dispute.
error NotInDispute();
/// @notice Thrown when attempting to confirm settlement before the dispute deadline (and caller is not the non-disputer).
error DisputePeriodNotPassed();
/// @notice Thrown when withdrawing more liquidity than available in the pool.
error InsufficientLiquidity();
/// @notice Thrown when Alice's ECDSA signature verification fails.
error InvalidAliceSignature();
/// @notice Thrown when Bob's ECDSA signature verification fails.
error InvalidBobSignature();
/// @notice Thrown when sha256(preimage) doesn't match the expected HTLC hash.
error InvalidPreimage();
/// @notice Thrown when a preimage is submitted after the HTLC resolution deadline.
error PaymentDeadlinePassed();
/// @notice Thrown for unrecognized OpType enum values in batchExecute.
error InvalidOpType();
/// @notice Thrown when a non-Native asset uses address(0), or a Native asset uses a non-zero address.
error InvalidAssetAddress();
/// @notice Thrown when alice == bob in a channel configuration.
error InvalidChannelParticipants();
/// @notice Thrown when the revocation signature doesn't recover to Alice or Bob.
error InvalidRevokerSignature();
/// @notice Thrown when block.timestamp + disputePeriod overflows uint64.
error InvalidDisputePeriod();
/// @notice Thrown when claimAsset is called but the user has no escrowed funds for the asset.
error NothingToClaim();

/// @dev Sentinel value stored in assetChannels when a channel is adversarially closed
///      (via confirmUnilateralSettlement or penalizeRevokedChannel). Prevents signature
///      replay across channel incarnations: closed channels cannot be reopened with the
///      same (alice, bob, channelNumber, asset) tuple. Parties must use a new channelNumber.
///      Cooperative closures (updateChannel with zero balances) do NOT set this sentinel —
///      the channel remains reusable with the same channelNumber.
///      `bytes32(1)` is safe because keccak256 outputs are uniformly distributed over 2^256;
///      collision with a fixed constant is negligible (probability ≈ 1/2^256).
bytes32 constant CLOSED_CHANNEL_SENTINEL = bytes32(uint256(1));
