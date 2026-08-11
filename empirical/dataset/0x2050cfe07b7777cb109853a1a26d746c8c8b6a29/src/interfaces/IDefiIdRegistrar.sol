//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDefiIdRegistrar {
  // ---- Enums ----

  enum HandleClass {
    Standard,
    Premium,
    Auction,
    Reserved,
    Blocked
  }

  /// @notice Payment cadence. Annual durations are counted in years (1–5) and receive
  ///         a 10% discount; Monthly durations are counted in months (1–60) at list price.
  enum PaymentCadence {
    Annual,
    Monthly
  }

  // ---- Errors: Registration ----

  error LabelExcluded();
  error LabelUnavailable();
  error AlreadyHasDefiId();
  error RegistrationPaused();
  error InvalidDuration();

  // ---- Errors: Subnames ----

  error ParentExpired();
  error NotOwner();
  error RegistrarNotApproved();

  // ---- Errors: Admin ----

  error InvalidExpiry();

  // ---- Errors: Renewal ----

  error NameExpired();
  error OnlyOwnerCanRenewInGrace();

  // ---- Errors: Whitelist ----

  error AlreadyClaimed();
  error InvalidMerkleProof();
  error InvalidSignature();
  error WhitelistNotActive();

  // ---- Errors: General ----

  error TransferFailed();
  error ZeroAddress();
  error ZeroNode();
  error ZeroPrice();

  // ---- Events: Issuance ----

  event NameRegistered(
    bytes32 indexed node, string label, address indexed owner, uint64 expiry, uint256 cost, uint8 handleClass
  );
  event NameRenewed(bytes32 indexed node, string label, uint64 newExpiry, uint256 cost);
  event SubnameCreated(bytes32 indexed parent, string label, bytes32 indexed node, address indexed owner);

  // ---- Events: Root Updates ----

  event ExcludedRootUpdated(bytes32 newRoot);
  event WhitelistRootUpdated(bytes32 newRoot);

  // ---- Events: Whitelist ----

  event WhitelistNameClaimed(
    bytes32 indexed node, string label, address indexed newOwner, address indexed originalAddress
  );

  // ---- Events: Admin ----

  event NameRevoked(bytes32 indexed node, string label);
  event BeneficiaryUpdated(address indexed newBeneficiary);
  event DefaultResolverUpdated(address indexed newResolver);
  event FundsRecovered(address indexed token, uint256 amount, address indexed to);

  // ---- Events: Pause ----

  event Paused();
  event Unpaused();

  // ---- Events: Pricing ----

  /// @notice Emitted when the monthly USDC prices are updated.
  event PricesUpdated(uint256 price3, uint256 price45, uint256 price67);
}
