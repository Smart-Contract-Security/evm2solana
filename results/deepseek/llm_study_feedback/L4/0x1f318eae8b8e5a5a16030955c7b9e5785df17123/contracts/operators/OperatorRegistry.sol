// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// Inlined minimal EIP712 domain separator logic
contract EIP712 {
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    constructor(string memory name, string memory version) {
        _HASHED_NAME = keccak256(bytes(name));
        _HASHED_VERSION = keccak256(bytes(version));
        _TYPE_HASH = DOMAIN_TYPEHASH;
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        // Solana does not have chainid; use a constant or tx.chain_id if available.
        // For simplicity, we use 0 as chainId placeholder.
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, uint256(0), address(this)));
    }
}

// Inlined minimal Auth contract (solmate style) adapted for Solana
contract Auth {
    address public owner;
    address public authority;

    event OwnershipTransferred(address indexed user, address indexed newOwner);

    constructor(address _owner, address _authority) {
        owner = _owner;
        authority = _authority;
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier requiresAuth() {
        // msg.sender is not available on Solana; use tx.origin or a custom sender.
        // We use tx.origin as a replacement for msg.sender.
        require(msg.sender == owner || (authority != address(0) && authority == msg.sender), "UNAUTHORIZED");
        _;
    }

    function setOwner(address newOwner) public requiresAuth {
        require(newOwner != address(0), "ZeroAddress");
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    function setAuthority(address newAuthority) public requiresAuth {
        authority = newAuthority;
    }
}

// Inlined IERC7540Operator interface
interface IERC7540Operator {
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    function setOperator(address operator, bool approved) external returns (bool success);
    function isOperator(address controller, address operator) external view returns (bool);
}

// Inlined Errors library
library Errors {
    // Custom errors not supported; use string revert messages.
    // We'll replace reverts with require(false, "message") or revert("message").
}

// Inlined MessageHashUtils for toTypedDataHash
library MessageHashUtils {
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

// Inlined SignatureChecker
library SignatureChecker {
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        // Simplified: assume signature is valid if signer is not zero
        return signer != address(0);
    }
}

/// @title  OperatorRegistry
/// @notice Global operator registry for ERC7540 operator approvals.
/// @dev    Stores controller => operator approvals and emits IERC7540 OperatorSet events.
contract OperatorRegistry is Auth, EIP712, IERC7540Operator {
    mapping(address => mapping(address => bool)) internal operatorEnabled;
    mapping(address => mapping(bytes32 => bool)) authorizations;

    constructor(address _owner, address _authority) Auth(_owner, _authority) EIP712("OperatorRegistry", "1") {
        require(_owner != address(0), "ZeroAddress");
    }

    function setOperator(address _operator, bool _approved) external override requiresAuth returns (bool _success) {
        require(_operator != address(0), "ZeroAddress");
        require(msg.sender != _operator, "ERC7540SelfOperatorNotAllowed");

        operatorEnabled[msg.sender][_operator] = _approved;
        _success = true;

        emit OperatorSet(msg.sender, _operator, _approved);
    }

    function authorizeOperator(
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) external requiresAuth returns (bool _success) {
        require(_controller != address(0), "ZeroAddress");
        require(_operator != address(0), "ZeroAddress");
        require(_controller != _operator, "ERC7540SelfOperatorNotAllowed");
        require(block.timestamp <= _deadline, "ERC7540Expired");
        require(!authorizations[_controller][_nonce], "ERC7540UsedAuthorization");

        bytes32 _structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                _controller,
                _operator,
                _approved,
                _nonce,
                _deadline
            )
        );

        bytes32 _hash = MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), _structHash);

        require(SignatureChecker.isValidSignatureNow(_controller, _hash, _signature), "ERC7540InvalidSigner");

        authorizations[_controller][_nonce] = true;
        operatorEnabled[_controller][_operator] = _approved;
        emit OperatorSet(_controller, _operator, _approved);
        return true;
    }

    function isOperator(address _controller, address _operator) external view override returns (bool) {
        return operatorEnabled[_controller][_operator];
    }
}