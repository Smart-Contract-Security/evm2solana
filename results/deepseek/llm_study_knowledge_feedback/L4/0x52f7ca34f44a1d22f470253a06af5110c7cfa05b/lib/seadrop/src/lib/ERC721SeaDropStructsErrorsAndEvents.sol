// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// On Solana, we cannot import from external files that define types not yet available.
// We must define all required structs locally.

struct PublicDrop {
    uint64 startTime;
    uint64 endTime;
    uint64 feeBps;
    bool restrictFeeRecipients;
    uint64 maxTotalMintsPerWallet;
    uint64 mintPrice;
    bytes32 merkleRoot;
}

struct AllowListData {
    bytes32 merkleRoot;
    address[] publicKeyHooks;
    bool allowListEnabled;
}

struct TokenGatedDropStage {
    uint64 mintPrice;
    uint64 maxTotalMintsPerWallet;
    uint64 startTime;
    uint64 endTime;
    uint64 dropStageIndex;
    uint64 maxTokenSupplyForStage;
    uint64 feeBps;
    bool restrictFeeRecipients;
    address nftToken;
    bytes32 merkleRoot;
}

struct SignedMintValidationParams {
    uint64 minMintPrice;
    uint64 maxMaxTotalMintsPerWallet;
    uint64 maxStartTime;
    uint64 maxEndTime;
    uint64 maxMaxTokenSupplyForStage;
    uint64 maxFeeBps;
    bool restrictFeeRecipients;
}

interface ERC721SeaDropStructsErrorsAndEvents {
    event SeaDropTokenDeployed();

    struct MultiConfigureStruct {
        uint64 maxSupply;
        string baseURI;
        string contractURI;
        address seaDropImpl;
        PublicDrop publicDrop;
        string dropURI;
        AllowListData allowListData;
        address creatorPayoutAddress;
        bytes32 provenanceHash;

        address[] allowedFeeRecipients;
        address[] disallowedFeeRecipients;

        address[] allowedPayers;
        address[] disallowedPayers;

        // Token-gated
        address[] tokenGatedAllowedNftTokens;
        TokenGatedDropStage[] tokenGatedDropStages;
        address[] disallowedTokenGatedAllowedNftTokens;

        // Server-signed
        address[] signers;
        SignedMintValidationParams[] signedMintValidationParams;
        address[] disallowedSigners;
    }
}