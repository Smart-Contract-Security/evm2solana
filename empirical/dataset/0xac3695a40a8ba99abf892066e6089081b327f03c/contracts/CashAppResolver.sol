// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IExtendedResolver {
    function resolve(bytes memory name, bytes memory data) external view returns (bytes memory);
}

error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

/// @title CashAppResolver
/// @notice ENSIP-10 wildcard + EIP-3668 CCIP-Read resolver for cash-app.eth.
/// @dev Holds no records onchain. Defers all resolution to a signed gateway.
contract CashAppResolver is IExtendedResolver, Ownable {
    string public gatewayUrl;
    mapping(address => bool) public signers;

    event GatewayUrlChanged(string newUrl);
    event SignerChanged(address indexed signer, bool authorized);

    constructor(string memory _gatewayUrl, address[] memory _signers) Ownable(msg.sender) {
        gatewayUrl = _gatewayUrl;
        for (uint256 i = 0; i < _signers.length; i++) {
            signers[_signers[i]] = true;
            emit SignerChanged(_signers[i], true);
        }
        emit GatewayUrlChanged(_gatewayUrl);
    }

    function setGatewayUrl(string calldata _gatewayUrl) external onlyOwner {
        gatewayUrl = _gatewayUrl;
        emit GatewayUrlChanged(_gatewayUrl);
    }

    function setSigner(address signer, bool authorized) external onlyOwner {
        signers[signer] = authorized;
        emit SignerChanged(signer, authorized);
    }

    /// @notice ENSIP-10 wildcard resolution. Always reverts OffchainLookup.
    function resolve(bytes calldata name, bytes calldata data) external view override returns (bytes memory) {
        bytes memory callData = abi.encode(name, data);
        string[] memory urls = new string[](1);
        urls[0] = gatewayUrl;
        revert OffchainLookup(
            address(this),
            urls,
            callData,
            this.resolveWithProof.selector,
            callData
        );
    }

    /// @notice CCIP-Read callback. Verifies the gateway signature and returns the result.
    /// @param response abi.encode(bytes result, uint64 expires, bytes sig)
    /// @param extraData The original (name, data) request, used to bind the signature.
    function resolveWithProof(bytes calldata response, bytes calldata extraData)
        external
        view
        returns (bytes memory)
    {
        (bytes memory result, uint64 expires, bytes memory sig) = abi.decode(response, (bytes, uint64, bytes));
        require(expires >= block.timestamp, "Signature expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                hex"1900",
                address(this),
                expires,
                keccak256(extraData),
                keccak256(result)
            )
        );

        address recovered = ECDSA.recover(digest, sig);
        require(signers[recovered], "Invalid signer");
        return result;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x9061b923 || // IExtendedResolver (ENSIP-10)
            interfaceId == 0x3b3b57de || // addr(bytes32)            — IAddrResolver (ENSIP-1)
            interfaceId == 0xf1cb7e06 || // addr(bytes32,uint256)    — IAddressResolver multichain (ENSIP-9/11)
            interfaceId == 0x59d1d43c || // text(bytes32,string)     — ITextResolver (ENSIP-5)
            interfaceId == 0x01ffc9a7;   // ERC165
    }
}
