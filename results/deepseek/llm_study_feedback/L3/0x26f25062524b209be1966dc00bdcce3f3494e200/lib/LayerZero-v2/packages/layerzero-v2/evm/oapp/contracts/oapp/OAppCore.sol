// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @dev Interface for the LayerZero Endpoint V2.
 */
interface ILayerZeroEndpointV2 {
    function setDelegate(address _delegate) external;
}

/**
 * @dev Interface for the OAppCore.
 */
interface IOAppCore {
    event PeerSet(uint32 eid, bytes32 peer);
}

/**
 * @dev Simple Ownable contract for Solana.
 * Note: Solang on Solana uses a different ownership model. We implement a basic version.
 */
contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/**
 * @title OAppCore
 * @dev Abstract contract implementing the IOAppCore interface with basic OApp configurations.
 */
abstract contract OAppCore is IOAppCore, Ownable {
    address public endpoint;

    mapping(uint32 => bytes32) public peers;

    constructor(address _endpoint, address _delegate) {
        endpoint = _endpoint;

        if (_delegate == address(0)) {
            revert("InvalidDelegate");
        }
        ILayerZeroEndpointV2(endpoint).setDelegate(_delegate);
    }

    function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
        _setPeer(_eid, _peer);
    }

    function _setPeer(uint32 _eid, bytes32 _peer) internal virtual {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
        bytes32 peer = peers[_eid];
        if (peer == bytes32(0)) {
            revert("NoPeer");
        }
        return peer;
    }

    function setDelegate(address _delegate) public onlyOwner {
        ILayerZeroEndpointV2(endpoint).setDelegate(_delegate);
    }
}