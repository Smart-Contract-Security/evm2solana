// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ERC721C } from "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import { ERC721OpenZeppelin } from "@limitbreak/creator-token-standards/src/token/erc721/ERC721OpenZeppelin.sol";
import { BasicRoyalties, ERC2981 } from "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import { OwnableBasic } from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import { Lifebuoy } from "solady/utils/Lifebuoy.sol";
import { IHeraldiaRenderer } from "./interfaces/IHeraldiaRenderer.sol";
import { IHeraldiaStorage } from "./interfaces/IHeraldiaStorage.sol";

contract Heraldia is ERC721C, BasicRoyalties, OwnableBasic, Lifebuoy {

    IHeraldiaRenderer public rendererContract;
    IHeraldiaStorage public storageContract;
    bool public storageContractLocked;

    uint256 private _totalSupply;

    mapping(address => bool) public minterAddresses;

    error NotMinter();
    error ExceedsMaxSupply();
    error URIQueryForNonExistentToken();
    error StorageLocked();

    event MinterAddressSet(address indexed minter, bool allowed);
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    constructor(
        IHeraldiaRenderer _renderer,
        IHeraldiaStorage _storage,
        address royaltyReceiver
    )
        ERC721OpenZeppelin("Heraldia", "HERALD")
        OwnableBasic()
        BasicRoyalties(royaltyReceiver, 500)
        Lifebuoy()
    {
        rendererContract = _renderer;
        storageContract = _storage;
    }

    modifier onlyMinters() {
        require(msg.sender == owner() || minterAddresses[msg.sender], NotMinter());
        _;
    }

    function maxSupply() public pure returns (uint256) {
        return 10_000;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), URIQueryForNonExistentToken());
        return rendererContract.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view virtual
        override(ERC721C, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function mint(address to, uint256 tokenId) external onlyMinters {
        require(_totalSupply < maxSupply(), ExceedsMaxSupply());
        require(tokenId < maxSupply(), ExceedsMaxSupply());
        _mint(to, tokenId);
        unchecked { _totalSupply++; }
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._afterTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0) && to != address(0)) {
            storageContract.incrementTransferCount(tokenId);
            emit MetadataUpdate(tokenId);
        }
    }

    // ─── Admin ────────────────────────────────────────

    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setRendererContract(IHeraldiaRenderer _renderer) external onlyOwner {
        rendererContract = _renderer;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setStorageContract(IHeraldiaStorage _storage) external onlyOwner {
        require(!storageContractLocked, StorageLocked());
        storageContract = _storage;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function lockStorageContract() external onlyOwner {
        storageContractLocked = true;
    }

    function setMinterAddresses(address[] calldata addresses, bool[] calldata allowed) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            minterAddresses[addresses[i]] = allowed[i];
            emit MinterAddressSet(addresses[i], allowed[i]);
        }
    }

    function signalMetadataUpdate() external onlyMinters {
        emit BatchMetadataUpdate(0, type(uint256).max);
    }
}