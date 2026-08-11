@program_id("AddressOfIWoolfGen2") interface IWoolfGen2 {
    function migrate(address[] calldata recipients, uint256[] calldata tokenIds) external;
}

contract WolfGameBridge {
    address public signerAddress;
    address public woolfGen2;

    mapping(uint256 => uint256) public mintIds;

    uint256 public currentTokenId;

    address private immutable _owner;

    constructor(address initialSignerAddress, address initialWoolfGen2Address) {
        require(initialSignerAddress != address(0), "Invalid signerAddress");
        require(initialWoolfGen2Address != address(0), "Invalid woolfGen2Address");

        _owner = tx.accounts.dataAccount.key;
        signerAddress = initialSignerAddress;
        woolfGen2 = initialWoolfGen2Address;
        currentTokenId = 24689;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    function mint(uint256 _mintId, bytes calldata _signature) external {
        require(mintIds[_mintId] == 0, "Already minted");

        bytes32 _messageHash = keccak256(abi.encode(tx.accounts.dataAccount.key, _mintId));
        address _recoveredAddress = recoverSigner(_messageHash, _signature);
        require(signerAddress == _recoveredAddress, "Invalid signature");

        uint256 tokenId = ++currentTokenId;
        mintIds[_mintId] = tokenId;

        address[] memory recipients = new address[](1);
        recipients[0] = tx.accounts.dataAccount.key;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        IWoolfGen2(woolfGen2).migrate{accounts: []}(recipients, tokenIds);
    }

    function updateSignerAddress(address newSignerAddress) external onlyOwner {
        require(newSignerAddress != address(0), "Invalid signerAddress");
        signerAddress = newSignerAddress;
    }

    function recoverSigner(bytes32 messageHash, bytes memory signature) private pure returns (address) {
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        r = bytes32(signature[0:32]);
        s = bytes32(signature[32:64]);
        v = uint8(signature[64]);
        
        if (v < 27) {
            v += 27;
        }
        
        require(v == 27 || v == 28, "Invalid v value");
        
        return recoverECDSASigner(ethSignedMessageHash, v, r, s);
    }

    function recoverECDSASigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes32 hashedMessage = keccak256(abi.encodePacked(hash));
        (bool success, bytes memory result) = address(0x0000000000000000000000000000000000000001).call(
            abi.encodeWithSignature("verifySignature(bytes32,bytes)", hashedMessage, signature)
        );
        require(success, "Signature verification failed");
        return abi.decode(result, (address));
    }
}