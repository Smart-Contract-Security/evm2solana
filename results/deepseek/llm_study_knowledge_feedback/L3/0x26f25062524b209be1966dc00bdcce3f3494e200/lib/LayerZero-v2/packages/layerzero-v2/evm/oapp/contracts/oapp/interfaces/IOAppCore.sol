// SPDX-License-Identifier: MIT

/**
 * @title ILayerZeroEndpointV2
 * @notice Interface for the LayerZero Endpoint V2, adapted for Solana.
 */
interface ILayerZeroEndpointV2 {
    function setDelegate(address _delegate) external;
}

/**
 * @title IOAppCore
 */
interface IOAppCore {
    event PeerSet(uint32 eid, bytes32 peer);

    function oAppVersion() external view returns (uint64 senderVersion, uint64 receiverVersion);

    function endpoint() external view returns (address iEndpoint);

    function peers(uint32 _eid) external view returns (bytes32 peer);

    function setPeer(uint32 _eid, bytes32 _peer) external;

    function setDelegate(address _delegate) external;
}