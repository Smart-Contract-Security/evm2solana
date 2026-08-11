// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IBackendSignerRegistry {
    function backendSigner() external view returns (address);
}

interface IMintCollection {
    function mint(address to) external payable;
}

/// @title BurnerDelegate
/// @notice EIP-7702 delegate implementation for burner EOAs.
///
///         When a user delegates their burner EOA to this contract via a type-4
///         (EIP-7702) transaction, the EOA's code becomes the 23-byte delegation
///         designator pointing here.  All calls are then forwarded to this
///         implementation, but `address(this)` equals the EOA address and storage
///         slots are the EOA's storage.
///
///         Functions are gated by backend-signed intents.  The backend signs a
///         typed hash that commits to `address(this)` (i.e. the specific burner EOA),
///         the target address, any amounts, a nonce, and the chain-id.  Nonces are
///         stored per-EOA (in the EOA's own storage when called via 7702) and are
///         single-use to prevent replay.
contract BurnerDelegate {
    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Immutables (set in implementation; read from implementation storage)
    // -------------------------------------------------------------------------

    IBackendSignerRegistry public immutable REGISTRY;
    IMintCollection public immutable MINT_CONTRACT;
    address public immutable TREASURY;

    // -------------------------------------------------------------------------
    // Per-EOA storage
    // -------------------------------------------------------------------------

    /// @dev Lives in the delegated EOA's storage when called via EIP-7702.
    mapping(uint256 => bool) private _usedNonces;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MintExecuted(address indexed to, uint256 nonce);
    event WithdrawExecuted(address indexed to, uint256 amount, uint256 nonce);
    event SweepExecuted(address indexed treasury, uint256 amount, uint256 nonce);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address mintContract, address registry, address treasury) {
        require(
            mintContract != address(0) && registry != address(0) && treasury != address(0),
            "zero addr"
        );
        MINT_CONTRACT = IMintCollection(mintContract);
        REGISTRY = IBackendSignerRegistry(registry);
        TREASURY = treasury;
    }

    receive() external payable {}

    // -------------------------------------------------------------------------
    // Intent actions
    // -------------------------------------------------------------------------

    /// @notice Mint an NFT to `to` on behalf of the delegated burner EOA.
    /// @dev The backend signs: keccak256("MINT" ++ address(this) ++ to ++ nonce ++ chainid).
    ///      `msg.value` must equal MintCollection.mintPrice(); it is forwarded to the
    ///      mint contract.
    function mintWithIntent(address to, uint256 nonce, bytes calldata signature) external payable {
        require(!_usedNonces[nonce], "nonce used");

        bytes32 messageHash =
            keccak256(abi.encodePacked("MINT", address(this), to, nonce, block.chainid));
        address signer =
            MessageHashUtils.toEthSignedMessageHash(messageHash).recover(signature);
        require(signer == REGISTRY.backendSigner(), "invalid signature");

        _usedNonces[nonce] = true;

        emit MintExecuted(to, nonce);
        MINT_CONTRACT.mint{value: msg.value}(to);
    }

    /// @notice Withdraw `amount` ETH from the burner EOA to `to`.
    /// @dev The backend signs: keccak256("WITHDRAW" ++ address(this) ++ to ++ amount ++ nonce ++ chainid).
    function withdrawWithIntent(address to, uint256 amount, uint256 nonce, bytes calldata signature)
        external
    {
        require(!_usedNonces[nonce], "nonce used");
        require(to != address(0), "zero to");
        require(amount > 0 && amount <= address(this).balance, "bad amount");

        bytes32 messageHash =
            keccak256(abi.encodePacked("WITHDRAW", address(this), to, amount, nonce, block.chainid));
        address signer =
            MessageHashUtils.toEthSignedMessageHash(messageHash).recover(signature);
        require(signer == REGISTRY.backendSigner(), "invalid signature");

        _usedNonces[nonce] = true;

        emit WithdrawExecuted(to, amount, nonce);
        (bool ok,) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }

    /// @notice Sweep all ETH in the burner EOA to TREASURY.
    /// @dev The backend signs: keccak256("SWEEP" ++ address(this) ++ nonce ++ chainid).
    function sweepToTreasury(uint256 nonce, bytes calldata signature) external {
        require(!_usedNonces[nonce], "nonce used");

        bytes32 messageHash =
            keccak256(abi.encodePacked("SWEEP", address(this), nonce, block.chainid));
        address signer =
            MessageHashUtils.toEthSignedMessageHash(messageHash).recover(signature);
        require(signer == REGISTRY.backendSigner(), "invalid signature");

        _usedNonces[nonce] = true;

        uint256 balance = address(this).balance;
        emit SweepExecuted(TREASURY, balance, nonce);
        if (balance > 0) {
            (bool ok,) = TREASURY.call{value: balance}("");
            require(ok, "sweep failed");
        }
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns whether `nonce` has been used in this EOA's storage.
    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return _usedNonces[nonce];
    }
}
