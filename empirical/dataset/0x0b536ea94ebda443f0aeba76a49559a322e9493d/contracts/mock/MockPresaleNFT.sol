// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Mock Presale Soulbound NFT
/// @notice Single-mint, non-transferable ERC721. Fixed fiat-denominated price
///         paid in ETH using a Chainlink ETH/fiat feed. Mints require a
///         signature from an authorized off-chain signer.
contract MockPresaleNFT is ERC721, Ownable, ReentrancyGuard {

    uint256 public constant PRICE_8 = 100 * 1e8;
    uint256 public constant MAX_SUPPLY = 500;

    string public termsURI;
    AggregatorV3Interface public priceFeed;
    address public authorizedSigner;
    uint256 public maxOracleStaleness = 1 hours;
    uint256 public startTimestamp;

    uint256 private _nextTokenId = 1;
    mapping(address => bool) public hasMinted;

    event Minted(address indexed buyer, uint256 indexed tokenId, uint256 ethPaid);
    event SignerUpdated(address indexed signer);
    event PriceFeedUpdated(address indexed feed);
    event StalenessUpdated(uint256 seconds_);
    event StartTimestampUpdated(uint256 startTimestamp);

    error AlreadyMinted();
    error SoldOut();
    error InvalidSignature();
    error InsufficientPayment();
    error StaleOracle();
    error InvalidOraclePrice();
    error TransferDisabled();
    error TransferFailed();
    error PresaleNotStarted();

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        string memory termsURI_,
        address priceFeed_,
        address authorizedSigner_,
        uint256 startTimestamp_,
        address owner_
    ) ERC721(tokenName, tokenSymbol) {
        termsURI = termsURI_;
        priceFeed = AggregatorV3Interface(priceFeed_);
        authorizedSigner = authorizedSigner_;
        startTimestamp = startTimestamp_;
        _transferOwnership(owner_);
    }

    function mint(bytes calldata signature) external payable nonReentrant {
        if (block.timestamp < startTimestamp) revert PresaleNotStarted();
        if (hasMinted[msg.sender]) revert AlreadyMinted();
        if (_nextTokenId > MAX_SUPPLY) revert SoldOut();
        if (!_verifySignature(msg.sender, signature)) revert InvalidSignature();

        uint256 required = quoteEth();
        if (msg.value < required) revert InsufficientPayment();

        hasMinted[msg.sender] = true;
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        emit Minted(msg.sender, tokenId, required);

        uint256 refund = msg.value - required;
        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            if (!ok) revert TransferFailed();
        }
    }

    function _verifySignature(address buyer, bytes calldata signature) internal view returns (bool) {
        bytes32 digest = keccak256(abi.encodePacked(buyer, address(this), block.chainid));
        address recovered = ECDSA.recover(ECDSA.toEthSignedMessageHash(digest), signature);
        return recovered == authorizedSigner && recovered != address(0);
    }

    /// @notice Returns the ETH (in wei) required to cover PRICE_8 at the
    ///         latest oracle answer. Frontends should add a slippage buffer.
    function quoteEth() public view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > maxOracleStaleness) revert StaleOracle();
        return (PRICE_8 * 1e18) / uint256(answer);
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function tokenURI(uint256) public view override returns (string memory) {
        return termsURI;
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override
    {
        if (from != address(0) && to != address(0)) revert TransferDisabled();
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function setAuthorizedSigner(address signer) external onlyOwner {
        authorizedSigner = signer;
        emit SignerUpdated(signer);
    }

    function setPriceFeed(address feed) external onlyOwner {
        priceFeed = AggregatorV3Interface(feed);
        emit PriceFeedUpdated(feed);
    }

    function setMaxOracleStaleness(uint256 seconds_) external onlyOwner {
        maxOracleStaleness = seconds_;
        emit StalenessUpdated(seconds_);
    }

    function setStartTimestamp(uint256 startTimestamp_) external onlyOwner {
        startTimestamp = startTimestamp_;
        emit StartTimestampUpdated(startTimestamp_);
    }

    function withdraw(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        if (!ok) revert TransferFailed();
    }
}
