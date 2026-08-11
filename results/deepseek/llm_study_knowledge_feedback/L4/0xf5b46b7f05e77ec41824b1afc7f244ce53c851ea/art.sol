// Copyright (c) 2026 fellowship.xyz

import 'solana';

contract ArtCollection {
    uint64 private immutable MAX_SUPPLY;

    address public royaltyReceiver;
    address public minter;
    address public metadataContract;

    uint64 public royaltyFraction;
    uint64 public royaltyDenominator = 100;
    uint64 public totalSupply;

    string public baseURI;

    event MetadataUpdate(uint256 tokenId);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    address private _owner;

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    modifier onlyMinter() {
        require(tx.accounts.dataAccount.key == minter, "Not minter");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI_,
        uint64 maxSupply,
        address royaltyReceiver_,
        uint64 royaltyPercent
    ) {
        require(maxSupply > 0, "Max supply must not be zero");
        require(royaltyReceiver_ != address(0), "Royalty receiver must not be the zero address");
        require(royaltyPercent <= 100, "Royalty fraction must not be greater than 100%");

        MAX_SUPPLY = maxSupply;
        baseURI = baseURI_;
        royaltyReceiver = royaltyReceiver_;
        royaltyFraction = royaltyPercent;
        _owner = tx.accounts.dataAccount.key;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function mint(address to, uint64 tokenId) public onlyMinter {
        require(tokenId > 0 && tokenId <= MAX_SUPPLY, "Invalid token ID");
        totalSupply++;
    }

    function mintRange(address to, uint64 idStart, uint64 idEnd) external onlyMinter {
        require(idStart > 0 && idEnd <= MAX_SUPPLY, "Invalid token range");
        require(idStart <= idEnd, "Start ID must be less than or equal to end ID");

        for (uint64 tokenId = idStart; tokenId <= idEnd; tokenId++) {
            mint(to, tokenId);
        }
    }

    function setMinter(address minter_) external onlyOwner {
        minter = minter_;
    }

    function setRoyaltyReceiver(address royaltyReceiver_) external onlyOwner {
        require(royaltyReceiver_ != address(0), "Royalty receiver must not be the zero address");
        royaltyReceiver = royaltyReceiver_;
    }

    function setRoyaltyFraction(uint64 royaltyFraction_, uint64 royaltyDenominator_) external onlyOwner {
        require(royaltyDenominator_ != 0, "Royalty denominator must not be zero");
        require(royaltyFraction_ <= royaltyDenominator_, "Royalty fraction must not be greater than 100%");
        royaltyFraction = royaltyFraction_;
        royaltyDenominator = royaltyDenominator_;
    }

    function updateBaseURI(string calldata baseURI_) external onlyOwner {
        require(bytes(baseURI_).length > 0, "New base URI must be provided");
        baseURI = baseURI_;
        metadataContract = address(0);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    function delegateTokenURIs(address delegate) external onlyOwner {
        require(delegate != address(0), "New metadata delegate must not be the zero address");
        baseURI = "";
        metadataContract = delegate;
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    function tokenURI(uint64 tokenId) public view returns (string memory) {
        require(tokenId > 0 && tokenId <= MAX_SUPPLY, "Invalid token ID");

        if (bytes(baseURI).length > 0) {
            return string(abi.encodePacked(baseURI, uint64ToString(tokenId), ".json"));
        }

        if (metadataContract != address(0)) {
            AccountMeta[1] memory metas = [
                AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: false})
            ];
            (bool success, bytes memory result) = metadataContract.call{program_id: metadataContract, accounts: metas}(abi.encodeWithSignature("tokenURI(uint64)", tokenId));
            require(success, "tokenURI call failed");
            return abi.decode(result, (string));
        }

        revert("tokenURI not configured");
    }

    function royaltyInfo(uint64, uint64 salePrice) external view returns (address receiver, uint64 royaltyAmount) {
        receiver = royaltyReceiver;
        royaltyAmount = mulDivCeil(salePrice, royaltyFraction, royaltyDenominator);
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x80ac58cd ||
            interfaceId == 0x5b5e139f ||
            interfaceId == 0x2a55205a ||
            interfaceId == 0x49064906 ||
            interfaceId == 0x7f5828d0 ||
            interfaceId == 0x01ffc9a7;
    }

    function uint64ToString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint64 temp = value;
        uint64 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function mulDivCeil(uint64 a, uint64 b, uint64 denominator) internal pure returns (uint64) {
        uint64 product = a * b;
        if (product % denominator == 0) {
            return product / denominator;
        } else {
            return product / denominator + 1;
        }
    }
}