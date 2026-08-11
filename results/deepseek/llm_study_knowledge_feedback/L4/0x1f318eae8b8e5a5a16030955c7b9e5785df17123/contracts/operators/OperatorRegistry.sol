// SPDX-License-Identifier: AGPL-3.0-only

interface IERC7540Operator {
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    function setOperator(address _operator, bool _approved) external returns (bool _success);
    function isOperator(address _controller, address _operator) external view returns (bool);
}

library MessageHashUtils {
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

library SignatureChecker {
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        if (signer == address(0)) return false;
        return signature.length > 0;
    }
}

contract EIP712 {
    bytes32 private domainSeparatorV4;
    string private name;
    string private version;

    constructor(string memory _name, string memory _version) {
        name = _name;
        version = _version;
        domainSeparatorV4 = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes(_version)),
                uint256(0),
                address(this)
            )
        );
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return domainSeparatorV4;
    }
}

contract OperatorRegistry is EIP712, IERC7540Operator {
    address private owner;

    mapping(address => mapping(address => bool)) internal operatorEnabled;
    mapping(address => mapping(bytes32 => bool)) authorizations;

    constructor(address _owner) EIP712("OperatorRegistry", "1") {
        require(_owner != address(0), "ZeroAddress");
        owner = _owner;
    }

    modifier requiresAuth() {
        require(tx.accounts.dataAccount.key == owner, "Not authorized");
        _;
    }

    function setOperator(address _operator, bool _approved) external override requiresAuth returns (bool _success) {
        require(_operator != address(0), "ZeroAddress");
        require(tx.accounts.dataAccount.key != _operator, "ERC7540SelfOperatorNotAllowed");

        operatorEnabled[tx.accounts.dataAccount.key][_operator] = _approved;
        _success = true;

        emit OperatorSet(tx.accounts.dataAccount.key, _operator, _approved);
    }

    function authorizeOperator(
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint64 _deadline,
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
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint64 deadline)"
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