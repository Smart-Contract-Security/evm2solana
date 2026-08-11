// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import "../interfaces/IAceDataQuality.sol";

contract AceDataQuality is AccessControl, EIP712, IAceDataQuality {
    bytes32 public constant DATA_QUALITY_SIGNER_ROLE = keccak256("DATA_QUALITY_SIGNER_ROLE");
    bytes32 public constant ATTESTATION_CONSUMER_ROLE = keccak256("ATTESTATION_CONSUMER_ROLE");
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_TIER = 2;

    bytes32 private constant ATTESTATION_TYPEHASH = keccak256(
        "DataQualityAttestation(address user,address consumer,uint256 roundId,uint8 tier,uint16 weightBps,uint256 deadline,uint256 nonce)"
    );

    mapping(address => uint256) public nonces;

    event DataQualityAttested(
        address indexed user,
        address indexed consumer,
        uint256 indexed roundId,
        uint8 tier,
        uint16 weightBps,
        uint256 nonce
    );

    error InvalidAddress();
    error InvalidTier();
    error InvalidWeight();
    error InvalidDeadline();
    error InvalidNonce();
    error InvalidConsumer();
    error InvalidSignature();

    constructor(address admin, address signer) EIP712("AceDataQuality", "1") {
        if (admin == address(0) || signer == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DATA_QUALITY_SIGNER_ROLE, signer);
    }

    function consumeAttestation(DataQualityAttestation calldata attestation, bytes calldata signature)
        external
        override
        onlyRole(ATTESTATION_CONSUMER_ROLE)
        returns (uint8 tier, uint16 weightBps)
    {
        if (attestation.user == address(0)) {
            revert InvalidAddress();
        }
        if (attestation.consumer != msg.sender) {
            revert InvalidConsumer();
        }
        if (attestation.tier > MAX_TIER) {
            revert InvalidTier();
        }
        if (attestation.weightBps == 0 || attestation.weightBps > BPS_DENOMINATOR) {
            revert InvalidWeight();
        }
        if (block.timestamp > attestation.deadline) {
            revert InvalidDeadline();
        }
        if (attestation.nonce != nonces[attestation.user]) {
            revert InvalidNonce();
        }

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ATTESTATION_TYPEHASH,
                    attestation.user,
                    attestation.consumer,
                    attestation.roundId,
                    attestation.tier,
                    attestation.weightBps,
                    attestation.deadline,
                    attestation.nonce
                )
            )
        );
        address recovered = ECDSA.recover(digest, signature);
        if (!hasRole(DATA_QUALITY_SIGNER_ROLE, recovered)) {
            revert InvalidSignature();
        }

        nonces[attestation.user] = attestation.nonce + 1;

        emit DataQualityAttested(
            attestation.user,
            attestation.consumer,
            attestation.roundId,
            attestation.tier,
            attestation.weightBps,
            attestation.nonce
        );

        return (attestation.tier, attestation.weightBps);
    }
}
