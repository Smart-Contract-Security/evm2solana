// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Custom error definitions
error InvalidTokenAddress();                    // Error when token address is zero
error TokenAmountMustBeGreaterThanZero();       // Error when token amount is zero
error ExpiryTimeMustBeInFuture();               // Error when expiry time is not in the future
error InvalidTakerAddress();                    // Error when taker address is zero
error RecordDoesNotExist();                     // Error when record does not exist
error RecordStatusNotLessThanAccepted();        // Error when record status is not less than COMPLETED status
error ExpiryTimeModificationLimitReached();     // Error when expiry time modification limit is reached
error CannotModifyExpiryTimeBeforeGracePeriod();// Error when trying to modify expiry time before grace period
error ExpiryTimeNotReached();                   // Error when expiry time is not reached
error OnlyTaker();                              // Error when non-taker tries to trigger some actions
error OnlyMaker();                              // Error when non-maker tries to trigger some actions
error RecordNotInValidStatus();                 // Error when record is not in a valid status
error InvalidSignature(address signer, address recover);                       // Error when signature is invalid
error RecordExpired();                          // Error when record has expired

contract Escrow is EIP712, Nonces {
    using SafeERC20 for IERC20;

    bytes32 private constant UPLOAD_PROOF_URL_TYPEHASH =
        keccak256("UploadProofUrl(uint256 recordId,string proofUrl,address signer,uint256 nonce)");

    bytes32 private constant DEPOSIT_TYPEHASH =
        keccak256("Deposit(address tokenAddress,uint256 tokenAmount,uint40 expiryTime,uint32 gracePeriod,address taker,address taker1,address signer,uint256 nonce)");

    bytes32 private constant MODIFY_EXPIRY_TIME_TYPEHASH =
        keccak256("ModifyExpiryTime(uint256 recordId,uint40 newExpiryTime,address signer,uint256 nonce)");

    bytes32 private constant CANCEL_RECORD_TYPEHASH =
        keccak256("CancelRecord(uint256 recordId,address signer,uint256 nonce)");

    bytes32 private constant ACCEPT_RECORD_TYPEHASH =
        keccak256("AcceptRecord(uint256 recordId,address signer,uint256 nonce)");

    // Use simple uint256 instead of Counters
    uint256 private _nextRecordId = 1;

    constructor() EIP712("Escrow", "1") {}

    // Record status
    enum Status {
        CREATED,
        COMPLETED,
        CANCELLED,
        EXPIRED
    }

    // Record structure
    struct Record {
        uint256 id;
        address tokenAddress;
        uint256 tokenAmount;
        uint40 expiryTime;         // Optimized: Unix timestamp fits in uint40 (enough until year 36812)
        uint32 gracePeriod;        // Optimized: 72 hours in seconds = 259200, fits in uint32
        address taker;             // Business-facing taker identity
        string proofUrl;
        Status status;
        uint8 expiryTimeModificationCount;
        address maker;             // Added maker address to store the record creator
        address taker1;            // Finance settlement account for taker
    }

    // Mapping from record ID to Record
    mapping(uint256 => Record) public records;

    // Events
    event RecordCreated(
        uint256 indexed recordId,
        address indexed maker,
        address indexed taker,
        address tokenAddress,
        uint256 tokenAmount,
        uint40 expiryTime,
        uint32 gracePeriod
    );

    event ProofUrlUploaded(uint256 indexed recordId);
    event RecordCancelled(uint256 indexed recordId, address indexed maker, uint256 amount);
    event ExpiryTimeModified(uint256 indexed recordId, uint40 oldExpiryTime, uint40 newExpiryTime);
    event FundsReleased(uint256 indexed recordId, address indexed taker, uint256 amount);

    /**
     * @dev Creates a new escrow record
     * @param tokenAddress The address of the token to be escrowed
     * @param tokenAmount The amount of tokens to be escrowed
     * @param expiryTime The expiry time of the escrow
     * @param gracePeriod The grace period (72 hours in seconds)
     * @param taker The taker's business-facing address
     * @param taker1 The taker's finance account that actually receives funds
     * @return recordId The ID of the created record
     */
    function deposit(
        address tokenAddress,
        uint256 tokenAmount,
        uint40 expiryTime,
        uint32 gracePeriod,
        address taker,
        address taker1
    ) external returns (uint256) {
        return _deposit(tokenAddress, tokenAmount, expiryTime, gracePeriod, taker, taker1, msg.sender);
    }

    /**
     * @dev Creates a new escrow record using a signature
     * @param tokenAddress The address of the token to be escrowed
     * @param tokenAmount The amount of tokens to be escrowed
     * @param expiryTime The expiry time of the escrow
     * @param gracePeriod The grace period (72 hours in seconds)
     * @param taker The taker's business-facing address
     * @param signer The address of the signer authorizing the deposit
     * @param signature The EIP-712 signature authorizing the deposit
     * @return recordId The ID of the created record
     */
    function sigDeposit(
        address tokenAddress,
        uint256 tokenAmount,
        uint40 expiryTime,
        uint32 gracePeriod,
        address taker,
        address taker1,
        address signer,
        bytes calldata signature
    ) external returns (uint256) {
        bytes memory abiEncode = abi.encode(DEPOSIT_TYPEHASH, tokenAddress, tokenAmount, expiryTime, gracePeriod, taker, taker1, signer, _useNonce(signer));
        _checkSignature(signer, signature, abiEncode);
        return _deposit(tokenAddress, tokenAmount, expiryTime, gracePeriod, taker, taker1, signer);
    }

    function _deposit(
        address tokenAddress,
        uint256 tokenAmount,
        uint40 expiryTime,
        uint32 gracePeriod,
        address taker,
        address taker1,
        address maker
    ) private returns (uint256) {
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        if (tokenAmount == 0) revert TokenAmountMustBeGreaterThanZero();
        if (expiryTime <= uint40(block.timestamp)) revert ExpiryTimeMustBeInFuture();
        if (taker == address(0) || taker1 == address(0)) revert InvalidTakerAddress();

        uint256 recordId = _nextRecordId;
        _nextRecordId++;

        records[recordId] = Record({
            id: recordId,
            tokenAddress: tokenAddress,
            tokenAmount: tokenAmount,
            expiryTime: expiryTime,
            gracePeriod: gracePeriod,
            taker: taker,
            proofUrl: "",
            status: Status.CREATED,
            expiryTimeModificationCount: 0,
            maker: maker,  // Store the creator's address
            taker1: taker1 // The funds will be sent here
        });

        // Transfer tokens from sender to contract
        IERC20(tokenAddress).safeTransferFrom(maker, address(this), tokenAmount);

        emit RecordCreated(
            recordId,
            maker,
            taker,
            tokenAddress,
            tokenAmount,
            expiryTime,
            gracePeriod
        );

        return recordId;
    }

    /**
     * @dev Allows the taker to cancel a record in CREATED status and refund the maker
     * Only the record taker can call this function
     * @param recordId The ID of the record to cancel
     */
    function cancelRecord(uint256 recordId) external {
        _cancelRecord(msg.sender, recordId);
    }

    /**
     * @dev Allows the taker to cancel a record using a signature
     * @param recordId The ID of the record to cancel
     * @param signer The address of the signer authorizing the cancellation
     * @param signature The EIP-712 signature authorizing the cancellation
     */
    function sigCancelRecord(uint256 recordId, address signer, bytes calldata signature) external {
        bytes memory abiEncode = abi.encode(CANCEL_RECORD_TYPEHASH, recordId, signer, _useNonce(signer));
        _checkSignature(signer, signature, abiEncode);
        _cancelRecord(signer, recordId);
    }

    function _cancelRecord(address signer, uint256 recordId) private {
        Record storage record = records[recordId];
        if (record.id != recordId) revert RecordDoesNotExist();
        if (uint40(block.timestamp) >= record.expiryTime) revert RecordExpired();
        if (record.taker != signer) revert OnlyTaker();
        if (record.status != Status.CREATED) revert RecordNotInValidStatus();

        record.status = Status.CANCELLED;

        // Return funds to the maker
        IERC20(record.tokenAddress).safeTransfer(record.maker, record.tokenAmount);

        emit RecordCancelled(recordId, record.maker, record.tokenAmount);
    }

    /**
     * @dev Allows the taker to upload a proof URL for a record
     * Only the record taker can call this function
     * @param recordId The ID of the record
     * @param proofUrl The proof URL
     */
    function uploadProofUrl(uint256 recordId, string calldata proofUrl) external  {
        _uploadProofUrl(msg.sender, recordId, proofUrl);
    }

    /**
     * @dev Allows the taker to upload a proof URL for a record using a signature
     * @param recordId The ID of the record
     * @param proofUrl The proof URL
     * @param signer The address of the signer authorizing the upload
     * @param signature The EIP-712 signature authorizing the upload
     */
    function sigUploadProofUrl(uint256 recordId, string calldata proofUrl, address signer, bytes calldata signature) external {
        bytes memory abiEncode = abi.encode(UPLOAD_PROOF_URL_TYPEHASH, recordId, keccak256(bytes(proofUrl)), signer, _useNonce(signer));
        _checkSignature(signer, signature, abiEncode);
        _uploadProofUrl(signer, recordId, proofUrl);
    }

    function _uploadProofUrl(address signer, uint256 recordId, string calldata proofUrl) private  {
        Record storage record = records[recordId];
        if (record.id != recordId) revert RecordDoesNotExist();
        if (record.taker != signer) revert OnlyTaker();

        record.proofUrl = proofUrl;
        emit ProofUrlUploaded(recordId);
    }

    /**
     * @dev Allows the taker to accept a record in CREATED status and release funds to taker1
     * Only the record taker can call this function
     * @param recordId The ID of the record to accept
     */
    function acceptRecord(uint256 recordId) external {
        _acceptRecord(msg.sender, recordId);
    }

    /**
     * @dev Allows the taker to accept a record using a signature
     * @param recordId The ID of the record to accept
     * @param signer The address of the signer authorizing the acceptance
     * @param signature The EIP-712 signature authorizing the acceptance
     */
    function sigAcceptRecord(uint256 recordId, address signer, bytes calldata signature) external {
        bytes memory abiEncode = abi.encode(ACCEPT_RECORD_TYPEHASH, recordId, signer, _useNonce(signer));
        _checkSignature(signer, signature, abiEncode);
        _acceptRecord(signer, recordId);
    }

    function _acceptRecord(address signer, uint256 recordId) private {
        Record storage record = records[recordId];
        if (record.id != recordId) revert RecordDoesNotExist();
        if (uint40(block.timestamp) >= record.expiryTime) revert RecordExpired();
        if (record.taker != signer) revert OnlyTaker();
        if (record.status != Status.CREATED) revert RecordNotInValidStatus();

        _releaseFunds(record, recordId);
    }

    /**
     * @dev Allows the user to modify the expiry time of a record (maximum 3 times)
     * Only the record maker can call this function
     * @param recordId The ID of the record
     * @param newExpiryTime The new expiry time
     */
    function modifyExpiryTime(uint256 recordId, uint40 newExpiryTime) external {
        _modifyExpiryTime(msg.sender, recordId, newExpiryTime);
    }

    /**
     * @dev Allows the maker to modify the expiry time of a record using a signature
     * @param recordId The ID of the record
     * @param newExpiryTime The new expiry time
     * @param signer The address of the signer authorizing the modification
     * @param signature The EIP-712 signature authorizing the modification
     */
    function sigModifyExpiryTime(uint256 recordId, uint40 newExpiryTime, address signer, bytes calldata signature) external {
        bytes memory abiEncode = abi.encode(MODIFY_EXPIRY_TIME_TYPEHASH, recordId, newExpiryTime, signer, _useNonce(signer));
        _checkSignature(signer, signature, abiEncode);
        _modifyExpiryTime(signer, recordId, newExpiryTime);
    }

    function _modifyExpiryTime(address signer, uint256 recordId, uint40 newExpiryTime) private {
        Record storage record = records[recordId];
        if (record.id != recordId) revert RecordDoesNotExist();
        if (uint40(block.timestamp) >= record.expiryTime) revert RecordExpired();
        if (record.status >= Status.COMPLETED) revert RecordStatusNotLessThanAccepted();
        if (record.expiryTimeModificationCount >= 3) revert ExpiryTimeModificationLimitReached();
        if (newExpiryTime <= uint40(block.timestamp)) revert ExpiryTimeMustBeInFuture();
        if (signer != record.maker) revert OnlyMaker();
        
        // Check if current time is less than expiry time minus grace period
        // This means we can only modify if we're NOT within the grace period
        if (uint40(block.timestamp) >= record.expiryTime - record.gracePeriod)
            revert CannotModifyExpiryTimeBeforeGracePeriod();

        uint40 oldExpiryTime = record.expiryTime;
        record.expiryTime = newExpiryTime;
        record.expiryTimeModificationCount++;

        emit ExpiryTimeModified(recordId, oldExpiryTime, newExpiryTime);
    }

    /**
     * @dev Allows anyone to trigger the release of funds if the expiry time has been reached
     * @param recordId The ID of the record
     */
    function triggerRelease(uint256 recordId) public {
        Record storage record = records[recordId];
        if (record.id != recordId) revert RecordDoesNotExist();
        if (uint40(block.timestamp) < record.expiryTime) revert ExpiryTimeNotReached();

        if (record.status == Status.CREATED) {
            record.status = Status.EXPIRED;

            // Return funds to the maker
            IERC20(record.tokenAddress).safeTransfer(record.maker, record.tokenAmount);

            emit FundsReleased(recordId, record.maker, record.tokenAmount);
        } else {
            // COMPLETED/CANCELLED/EXPIRED: already finalized
            revert RecordNotInValidStatus();
        }
    }

    /**
     * @dev Allows anyone to trigger the release of funds for multiple records in a single transaction
     * If any record fails validation, the entire transaction will be reverted
     * @param recordIds An array of record IDs to process
     */
    function batchTriggerRelease(uint256[] calldata recordIds) external {
        for (uint256 i = 0; i < recordIds.length; i++) {
            triggerRelease(recordIds[i]);
        }
    }

    /**
     * @dev Returns a single record by its ID
     * @param recordId The ID of the record to retrieve
     * @return Record struct containing all record data
     */
    function getRecord(uint256 recordId) external view returns (Record memory) {
        Record storage record = records[recordId];
        if (record.id != recordId) revert RecordDoesNotExist();
        return record;
    }

    /**
     * @dev Returns multiple records by their IDs
     * @param recordIds Array of record IDs to retrieve
     * @return Array of Record structs containing all records' data
     */
    function getBatchRecords(uint256[] calldata recordIds) external view returns (Record[] memory) {
        Record[] memory batchRecords = new Record[](recordIds.length);
        
        for (uint256 i = 0; i < recordIds.length; i++) {
            Record storage record = records[recordIds[i]];
            if (record.id != recordIds[i]) revert RecordDoesNotExist();
            batchRecords[i] = record;
        }
        
        return batchRecords;
    }

    function _releaseFunds(Record storage record, uint256 recordId) private {
        record.status = Status.COMPLETED;
        IERC20(record.tokenAddress).safeTransfer(record.taker1, record.tokenAmount);
        // Event keeps the business-facing taker identity; actual transfer goes to taker1.
        emit FundsReleased(recordId, record.taker, record.tokenAmount);
    }

    function _checkSignature(address signer, bytes calldata signature, bytes memory abiEncode) private view {
        bytes32 digest = _hashTypedDataV4(keccak256(abiEncode));
        address recover = ECDSA.recover(digest, signature);
        if (signer != recover) revert InvalidSignature(signer, recover);
    }

}
