// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

import {ERC721A, IERC721A} from "erc721a/contracts/ERC721A.sol";
import {ERC721AQueryable} from "erc721a/contracts/extensions/ERC721AQueryable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

error ArrayLengthMismatch();
error DeadlineExpired();
error InvalidAddress();
error InvalidPhase();
error InvalidMintPrice();
error InvalidQuantity();
error InvalidReserveSupply();
error InvalidSignature();
error MaxAllowanceReached();
error MaxSupplyReached();
error PhaseNotActive();
error TradingLocked();
error TradingAlreadyOpen();
error WithdrawalFailed();
error WrongEtherAmount();

contract GreenAcres is ERC721A, ERC721AQueryable, ERC2981, Ownable, EIP712 {
    enum Phase {
        Closed,
        Guaranteed,
        FCFS,
        Extra,
        Public
    }

    uint256 public constant MAX_SUPPLY = 4_000;
    uint256 public constant INITIAL_MINT_PRICE = 0.019 ether;
    uint256 public constant INITIAL_RESERVED_SUPPLY = 2_000;
    uint256 public constant GUARANTEED_MAX_ALLOWANCE = 5;
    uint256 public constant FCFS_MAX_ALLOWANCE = 3;
    uint256 public constant EXTRA_MAX_ALLOWANCE = 3;
    uint256 public constant PUBLIC_MAX_PER_WALLET = 3;

    bytes32 private constant ALLOWLIST_MINT_TYPEHASH =
        keccak256(
            "AllowlistMint(address minter,uint8 phase,uint256 allowance,uint256 deadline)"
        );

    address public signer;
    string private _tokenBaseUri;

    uint256 public mintPrice = INITIAL_MINT_PRICE;
    Phase public activePhase;
    bool public tradingOpen;
    uint256 public reservedSupply = INITIAL_RESERVED_SUPPLY;
    uint256 public reserveMinted;
    uint256 public paidMinted;

    mapping(address => mapping(Phase => uint256)) public allowlistMinted;
    mapping(address => uint256) public publicMinted;

    constructor(
        address deployer,
        address initialSigner,
        string memory baseUri
    ) ERC721A("Green Acres", "ACRE") EIP712("Green Acres", "1") {
        if (deployer == address(0) || initialSigner == address(0)) {
            revert InvalidAddress();
        }

        signer = initialSigner;
        _tokenBaseUri = baseUri;
        _setDefaultRoyalty(deployer, 590);
        _transferOwnership(deployer);
        reserveMinted = 1;
        _mint(deployer, 1);
    }

    function mintAllowlist(
        Phase phase,
        uint256 allowance,
        uint256 quantity,
        uint256 deadline,
        bytes calldata signature
    ) external payable {
        if (phase == Phase.Closed || phase == Phase.Public) revert InvalidPhase();
        if (phase != activePhase) revert PhaseNotActive();
        if (quantity == 0) revert InvalidQuantity();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (msg.value != quantity * mintPrice) revert WrongEtherAmount();

        uint256 maxAllowance = _maxAllowanceForPhase(phase);
        if (allowance == 0 || allowance > maxAllowance) revert InvalidQuantity();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ALLOWLIST_MINT_TYPEHASH,
                    msg.sender,
                    uint8(phase),
                    allowance,
                    deadline
                )
            )
        );
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != signer) revert InvalidSignature();

        uint256 minted = allowlistMinted[msg.sender][phase];
        if (minted + quantity > allowance) revert MaxAllowanceReached();

        _consumePaidSupply(quantity);
        allowlistMinted[msg.sender][phase] = minted + quantity;
        paidMinted += quantity;
        _mint(msg.sender, quantity);
    }

    function mintPublic(uint256 quantity) external payable {
        if (activePhase != Phase.Public) revert PhaseNotActive();
        if (quantity == 0) revert InvalidQuantity();
        if (msg.value != quantity * mintPrice) revert WrongEtherAmount();

        uint256 minted = publicMinted[msg.sender];
        if (minted + quantity > PUBLIC_MAX_PER_WALLET) {
            revert MaxAllowanceReached();
        }

        _consumePaidSupply(quantity);
        publicMinted[msg.sender] = minted + quantity;
        paidMinted += quantity;
        _mint(msg.sender, quantity);
    }

    function batchAirdrop(
        address[] calldata recipients,
        uint256[] calldata quantities
    ) external onlyOwner {
        if (recipients.length != quantities.length) revert ArrayLengthMismatch();
        if (recipients.length == 0) revert InvalidQuantity();

        uint256 totalQuantity;
        for (uint256 i = 0; i < recipients.length; ) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (quantities[i] == 0) revert InvalidQuantity();
            totalQuantity += quantities[i];
            unchecked {
                ++i;
            }
        }

        if (reserveMinted + totalQuantity > reservedSupply) {
            revert MaxSupplyReached();
        }
        if (_totalMinted() + totalQuantity > MAX_SUPPLY) {
            revert MaxSupplyReached();
        }

        reserveMinted += totalQuantity;
        for (uint256 i = 0; i < recipients.length; ) {
            _mint(recipients[i], quantities[i]);
            unchecked {
                ++i;
            }
        }
    }

    function enableTrading() external onlyOwner {
        if (tradingOpen) revert TradingAlreadyOpen();
        tradingOpen = true;
    }

    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidAddress();
        signer = newSigner;
    }

    function setBaseURI(string calldata newBaseUri) external onlyOwner {
        _tokenBaseUri = newBaseUri;
    }

    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        if (newMintPrice == 0) revert InvalidMintPrice();
        mintPrice = newMintPrice;
    }

    function setReservedSupply(uint256 newReservedSupply) external onlyOwner {
        if (
            newReservedSupply < reserveMinted ||
            paidMinted > MAX_SUPPLY - newReservedSupply
        ) {
            revert InvalidReserveSupply();
        }
        reservedSupply = newReservedSupply;
    }

    function setActivePhase(Phase phase) external onlyOwner {
        activePhase = phase;
    }

    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        if (!success) revert WithdrawalFailed();
    }

    function totalSupply() public view override(ERC721A, IERC721A) returns (uint256) {
        return _totalMinted();
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseUri;
    }

    function _maxAllowanceForPhase(Phase phase) private pure returns (uint256) {
        if (phase == Phase.Guaranteed) return GUARANTEED_MAX_ALLOWANCE;
        if (phase == Phase.FCFS) return FCFS_MAX_ALLOWANCE;
        if (phase == Phase.Extra) return EXTRA_MAX_ALLOWANCE;
        revert InvalidPhase();
    }

    function _consumePaidSupply(uint256 quantity) private view {
        if (paidMinted + quantity > MAX_SUPPLY - reservedSupply) {
            revert MaxSupplyReached();
        }
        if (_totalMinted() + quantity > MAX_SUPPLY) {
            revert MaxSupplyReached();
        }
    }

    function approve(
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) {
        if (!tradingOpen) revert TradingLocked();
        super.approve(to, tokenId);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721A, IERC721A) {
        if (!tradingOpen) revert TradingLocked();
        super.setApprovalForAll(operator, approved);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721A, IERC721A, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override(ERC721A) {
        if (!tradingOpen && from != address(0) && to != address(0)) {
            revert TradingLocked();
        }
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }
}
