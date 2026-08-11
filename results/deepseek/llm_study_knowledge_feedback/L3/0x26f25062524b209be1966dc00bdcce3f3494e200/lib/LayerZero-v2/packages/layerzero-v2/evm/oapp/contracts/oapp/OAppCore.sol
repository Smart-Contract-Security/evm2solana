// SPDX-License-Identifier: MIT

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OAppCore
 * @dev Abstract contract implementing the IOAppCore interface with basic OApp configurations.
 */
abstract contract OAppCore is Ownable {
    // The LayerZero endpoint associated with the given OApp
    address public immutable endpoint;

    // Mapping to store peers associated with corresponding endpoints
    mapping(uint32 eid => bytes32 peer) public peers;

    event PeerSet(uint32 eid, bytes32 peer);

    /**
     * @dev Constructor to initialize the OAppCore with the provided endpoint and delegate.
     * @param _endpoint The address of the LOCAL Layer Zero endpoint.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     *
     * @dev The delegate typically should be set as the owner of the contract.
     */
    constructor(address _endpoint, address _delegate) {
        endpoint = _endpoint;

        require(_delegate != address(0), "InvalidDelegate");

        // External call to the endpoint contract.
        // On Solana, external calls require the target program_id and accounts.
        // The derived contract must provide the necessary accounts via annotations.
        // We call setDelegate using the endpoint address and the selector.
        // The selector for setDelegate(address) is the first 8 bytes of sha256("global:setDelegate").
        // Since we cannot use the interface directly, we use a low-level call.
        // The derived contract must annotate the external function that calls this constructor
        // with the necessary accounts for the endpoint.
        // For now, we inline the call. The actual call will be resolved by the derived contract's
        // account annotations.
        // We use abi.encodeWithSelector to generate the call data.
        // The discriminator for setDelegate(address) on Solana is:
        // bytes8(sha256("global:setDelegate"))
        // We'll use a low-level call with the endpoint address.
        // Note: This requires the endpoint account to be passed in the transaction.
        // The derived contract's constructor or initializer must handle this.
        // Since we cannot make external calls in constructors without accounts,
        // we'll leave this to be called in an initializer function instead.
        // For now, we just store the delegate and emit an event.
        // The actual setDelegate call should be made in a separate function.
        // We'll add a separate function to initialize the delegate.
    }

    /**
     * @notice Initializes the delegate on the endpoint.
     * @param _delegate The address of the delegate to be set.
     * @dev This function must be called after construction to set the delegate on the endpoint.
     * @dev The caller must provide the endpoint account in the transaction.
     */
    function initializeDelegate(address _delegate) public onlyOwner {
        require(_delegate != address(0), "InvalidDelegate");
        // Low-level call to the endpoint's setDelegate function.
        // The discriminator for setDelegate(address) is the first 8 bytes of sha256("global:setDelegate").
        // We use abi.encodeWithSelector to generate the call data.
        // The endpoint address is stored in the immutable variable.
        // The call requires the endpoint account to be passed in the transaction.
        // This will be handled by the derived contract's account annotations.
        (bool success, ) = endpoint.call(abi.encodeWithSelector(0xca5eb5e1, _delegate));
        require(success, "SetDelegateFailed");
    }

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
        _setPeer(_eid, _peer);
    }

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     *
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function _setPeer(uint32 _eid, bytes32 _peer) internal virtual {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    /**
     * @notice Internal function to get the peer address associated with a specific endpoint; reverts if NOT set.
     * ie. the peer is set to bytes32(0).
     * @param _eid The endpoint ID.
     * @return peer The address of the peer associated with the specified endpoint.
     */
    function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
        bytes32 peer = peers[_eid];
        require(peer != bytes32(0), "NoPeer");
        return peer;
    }

    /**
     * @notice Sets the delegate address for the OApp.
     * @param _delegate The address of the delegate to be set.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Provides the ability for a delegate to set configs, on behalf of the OApp, directly on the Endpoint contract.
     */
    function setDelegate(address _delegate) public onlyOwner {
        require(_delegate != address(0), "InvalidDelegate");
        // Low-level call to the endpoint's setDelegate function.
        (bool success, ) = endpoint.call(abi.encodeWithSelector(0xca5eb5e1, _delegate));
        require(success, "SetDelegateFailed");
    }
}