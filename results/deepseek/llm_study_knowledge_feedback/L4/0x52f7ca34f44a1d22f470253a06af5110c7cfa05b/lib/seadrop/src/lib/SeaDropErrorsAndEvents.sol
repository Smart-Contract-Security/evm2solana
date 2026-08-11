// SPDX-License-Identifier: MIT

// Note: Solana does not support importing structs from other files in the same way.
// We define the structs inline here.

struct PublicDrop {
    uint64 mintPrice;
    uint64 startTime;
    uint64 endTime;
    uint64 maxTotalMintableByWallet;
    uint64 feeBps;
    bool restrictFeeRecipients;
}

struct TokenGatedDropStage {
    uint64 mintPrice;
    uint64 maxTotalMintableByWallet;
    uint64 maxTokenSupplyForStage;
    uint64 dropStageIndex;
    uint64 startTime;
    uint64 endTime;
    uint64 feeBps;
    bool restrictFeeRecipients;
    address allowedNftToken;
    uint64 allowedNftTokenId;
}

struct SignedMintValidationParams {
    uint64 minMintPrice;
    uint64 maxMaxTotalMintableByWallet;
    uint64 minStartTime;
    uint64 maxEndTime;
    uint64 maxMaxTokenSupplyForStage;
    uint64 minFeeBps;
    uint64 maxFeeBps;
}

interface SeaDropErrorsAndEvents {
    // Note: Solana does not support custom errors with parameters.
    // We use events to log error information instead.

    event NotActive(
        uint64 currentTimestamp,
        uint64 startTimestamp,
        uint64 endTimestamp
    );

    event MintQuantityCannotBeZero();

    event MintQuantityExceedsMaxMintedPerWallet(uint64 total, uint64 allowed);

    event MintQuantityExceedsMaxSupply(uint64 total, uint64 maxSupply);

    event MintQuantityExceedsMaxTokenSupplyForStage(
        uint64 total,
        uint64 maxTokenSupplyForStage
    );

    event FeeRecipientCannotBeZeroAddress();

    event FeeRecipientNotPresent();

    event InvalidFeeBps(uint64 feeBps);

    event DuplicateFeeRecipient();

    event FeeRecipientNotAllowed();

    event CreatorPayoutAddressCannotBeZeroAddress();

    event IncorrectPayment(uint64 got, uint64 want);

    event InvalidProof();

    event SignerCannotBeZeroAddress();

    event InvalidSignature(address recoveredSigner);

    event SignerNotPresent();

    event PayerNotPresent();

    event DuplicatePayer();

    event PayerNotAllowed();

    event PayerCannotBeZeroAddress();

    event OnlyINonFungibleSeaDropToken(address sender);

    event TokenGatedNotTokenOwner(
        address nftContract,
        address allowedNftToken,
        uint64 allowedNftTokenId
    );

    event TokenGatedTokenIdAlreadyRedeemed(
        address nftContract,
        address allowedNftToken,
        uint64 allowedNftTokenId
    );

    event TokenGatedDropStageNotPresent();

    event TokenGatedDropAllowedNftTokenCannotBeZeroAddress();

    event TokenGatedDropAllowedNftTokenCannotBeDropToken();

    event InvalidSignedMintPrice(uint64 got, uint64 minimum);

    event InvalidSignedMaxTotalMintableByWallet(uint64 got, uint64 maximum);

    event InvalidSignedStartTime(uint64 got, uint64 minimum);

    event InvalidSignedEndTime(uint64 got, uint64 maximum);

    event InvalidSignedMaxTokenSupplyForStage(uint64 got, uint64 maximum);

    event InvalidSignedFeeBps(uint64 got, uint64 minimumOrMaximum);

    event SignedMintsMustRestrictFeeRecipients();

    event SignatureAlreadyUsed();

    // Note: indexed has no effect on Solana, but kept for interface compatibility.
    event SeaDropMint(
        address nftContract,
        address minter,
        address feeRecipient,
        address payer,
        uint64 quantityMinted,
        uint64 unitMintPrice,
        uint64 feeBps,
        uint64 dropStageIndex
    );

    event PublicDropUpdated(
        address nftContract,
        PublicDrop publicDrop
    );

    event TokenGatedDropStageUpdated(
        address nftContract,
        address allowedNftToken,
        TokenGatedDropStage dropStage
    );

    event AllowListUpdated(
        address nftContract,
        bytes32 previousMerkleRoot,
        bytes32 newMerkleRoot,
        string[] publicKeyURI,
        string allowListURI
    );

    event DropURIUpdated(address nftContract, string newDropURI);

    event CreatorPayoutAddressUpdated(
        address nftContract,
        address newPayoutAddress
    );

    event AllowedFeeRecipientUpdated(
        address nftContract,
        address feeRecipient,
        bool allowed
    );

    event SignedMintValidationParamsUpdated(
        address nftContract,
        address signer,
        SignedMintValidationParams signedMintValidationParams
    );

    event PayerUpdated(
        address nftContract,
        address payer,
        bool allowed
    );
}