@program_id("MandaliaStorage")
contract MandaliaStorage {
    address public nft;

    mapping(uint256 => bytes32) private _seeds;
    mapping(uint256 => uint16) private _txCounts;

    uint constant NOT_NFT_ERROR = 1;
    uint constant ALREADY_INITIALIZED_ERROR = 2;

    @payer(payer)
    @space(8 + 32 + 4 + 4)
    constructor(address payer) {
        nft = address(0);
    }

    function init(address nft_) external {
        if (nft != address(0)) {
            revert();
        }
        nft = nft_;
    }

    function setSeed(uint256 tokenId, bytes32 seed) external {
        if (tx.accounts.dataAccount.key != nft) {
            revert();
        }
        _seeds[tokenId] = seed;
    }

    function incrementTransferCount(uint256 tokenId) external {
        if (tx.accounts.dataAccount.key != nft) {
            revert();
        }
        unchecked { _txCounts[tokenId]++; }
    }

    function seedOf(uint256 tokenId) external view returns (bytes32) {
        return _seeds[tokenId];
    }

    function transferCountOf(uint256 tokenId) external view returns (uint16) {
        return _txCounts[tokenId];
    }
}