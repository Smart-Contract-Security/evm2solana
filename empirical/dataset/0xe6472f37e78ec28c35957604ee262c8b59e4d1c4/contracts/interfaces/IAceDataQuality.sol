// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IAceDataQuality {
    struct DataQualityAttestation {
        address user;
        address consumer;
        uint256 roundId;
        uint8 tier;
        uint16 weightBps;
        uint256 deadline;
        uint256 nonce;
    }

    function consumeAttestation(DataQualityAttestation calldata attestation, bytes calldata signature)
        external
        returns (uint8 tier, uint16 weightBps);
}
