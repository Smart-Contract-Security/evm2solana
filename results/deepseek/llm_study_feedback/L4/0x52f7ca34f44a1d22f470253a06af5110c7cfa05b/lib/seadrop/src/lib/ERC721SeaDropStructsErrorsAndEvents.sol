// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Inline the required structs since the import path is not available
struct AllowListData {
    bytes32 merkleRoot;
    string publicKeyURI;
    string uri;
}

struct PublicDrop {
    uint80 mintPrice;
    uint48 startTime;
    uint48 endTime;
    uint16 maxTotalMintableByWallet;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

struct SignedMintValidationParams {
    uint80 minMintPrice;
    uint24 maxMaxTotalMintableByWallet;
    uint40 minMaxTotalMintableByWallet;
    uint40 maxTokenSupplyForStage;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

struct TokenGatedDropStage {
    uint80 mintPrice;
    uint16 maxTotalMintableByWallet;
    uint48 startTime;
    uint48 endTime;
    uint8 maxTokenSupplyForStage;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

interface ERC721SeaDropStructsErrorsAndEvents {
  /**
   * @notice Revert with an error if mint exceeds the max supply.
   */
  error MintQuantityExceedsMaxSupply(uint256 total, uint256 maxSupply);

  /**
   * @notice Revert with an error if the number of token gated 
   *         allowedNftTokens doesn't match the length of supplied
   *         drop stages.
   */
  error TokenGatedMismatch();

  /**
   *  @notice Revert with an error if the number of signers doesn't match
   *          the length of supplied signedMintValidationParams
   */
  error SignersMismatch();

  /**
   * @notice An event to signify that a SeaDrop token contract was deployed.
   */
  event SeaDropTokenDeployed();

  /**
   * @notice A struct to configure multiple contract options at a time.
   */
  struct MultiConfigureStruct {
    uint256 maxSupply;
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