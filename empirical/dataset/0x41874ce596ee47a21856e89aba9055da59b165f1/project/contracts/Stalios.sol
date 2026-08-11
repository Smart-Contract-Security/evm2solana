// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//Stalios 

// Website : stalios.com
// Community: chat.stalios.com
// Twitter: x.com/0xStalios

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract Stalios {
    using SafeERC20 for IERC20;

    IERC20 public immutable paymentToken;
    address public immutable signer;
    address public immutable treasury;
    uint256 public immutable registrationFee;
    uint256 public constant MAX_USERNAME_LENGTH = 32;

    mapping(string => address) public usernameOwner;
    mapping(address => string) public usernameOf;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    event UsernameRegistered(
        address indexed user,
        string username,
        uint256 amount,
        uint256 nonce,
        bytes32 digest
    );

    error InvalidAddress();
    error EmptyUsername();
    error UsernameTooLong();
    error InvalidUsernameCharacter();
    error UsernameTaken();
    error AlreadyRegistered();
    error NonceAlreadyUsed();
    error SignatureExpired();
    error InvalidAmount();
    error InvalidSignature();

    constructor(
        address paymentToken_,
        address signer_,
        address treasury_,
        uint256 registrationFee_
    ) {
        if (paymentToken_ == address(0) || signer_ == address(0) || treasury_ == address(0)) {
            revert InvalidAddress();
        }
        paymentToken = IERC20(paymentToken_);
        signer = signer_;
        treasury = treasury_;
        registrationFee = registrationFee_;
    }

    function registerUsername(
        string calldata username,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (deadline < block.timestamp) revert SignatureExpired();
        if (amount != registrationFee) revert InvalidAmount();
        if (usedNonces[msg.sender][nonce]) revert NonceAlreadyUsed();

        bytes32 usernameHash = _validateAndHashUsername(username);
        bytes32 digest = _buildDigest(msg.sender, usernameHash, amount, nonce, deadline);
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(digest);
        address recovered = ECDSA.recover(ethHash, signature);
        if (recovered != signer) revert InvalidSignature();

        if (usernameOwner[username] != address(0)) revert UsernameTaken();
        if (bytes(usernameOf[msg.sender]).length != 0) revert AlreadyRegistered();

        usedNonces[msg.sender][nonce] = true;
        usernameOwner[username] = msg.sender;
        usernameOf[msg.sender] = username;
        paymentToken.safeTransferFrom(msg.sender, treasury, amount);

        emit UsernameRegistered(msg.sender, username, amount, nonce, digest);
    }

    function buildRegistrationDigest(
        address user,
        string calldata username,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) external view returns (bytes32) {
        bytes32 usernameHash = _validateAndHashUsername(username);
        return _buildDigest(user, usernameHash, amount, nonce, deadline);
    }

    function _buildDigest(
        address user,
        bytes32 usernameHash,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), block.chainid, user, usernameHash, amount, nonce, deadline));
    }

    function _validateAndHashUsername(string calldata username) internal pure returns (bytes32) {
        bytes calldata raw = bytes(username);
        uint256 len = raw.length;
        if (len == 0) revert EmptyUsername();
        if (len > MAX_USERNAME_LENGTH) revert UsernameTooLong();

        for (uint256 i = 0; i < len; i++) {
            bytes1 c = raw[i];
            bool isLowerAlpha = c >= 0x61 && c <= 0x7a; // a-z
            bool isDigit = c >= 0x30 && c <= 0x39; // 0-9
            bool isUnderscore = c == 0x5f; // _
            if (!isLowerAlpha && !isDigit && !isUnderscore) {
                revert InvalidUsernameCharacter();
            }
        }

        return keccak256(raw);
    }
}
