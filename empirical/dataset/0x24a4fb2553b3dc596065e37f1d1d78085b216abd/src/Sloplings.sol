// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableBasic} from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import {ERC721C, ERC721OpenZeppelin} from "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import {ICreatorToken} from "@limitbreak/creator-token-standards/src/interfaces/ICreatorToken.sol";
import {ICreatorTokenLegacy} from "@limitbreak/creator-token-standards/src/interfaces/ICreatorTokenLegacy.sol";
import {
    BasicRoyaltiesBase,
    ERC2981
} from "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface ISloplingsSlopToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract Sloplings is OwnableBasic, ERC721C, BasicRoyaltiesBase, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MIN_TOKEN_ID = 1;
    uint256 public constant MAX_TOKEN_ID = 10_000;
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant FEED_INTERVAL = 30 days;
    uint256 public constant FEED_COST = 1 ether;
    uint256 public constant REVIVE_COST = 10 ether;
    uint256 public constant IMMORTAL_COST = 100 ether;
    uint256 public constant MAX_IMMORTAL_SUPPLY = 1_000;

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum SloplingState {
        Alive,
        Starving,
        Dead,
        Immortal
    }

    error InvalidTokenId(uint256 tokenId);
    error DeadSlopling();
    error ImmortalLimitReached();
    error ImmortalSlopling();
    error InvalidFeedPeriods();
    error NotDeadSlopling();
    error NonTransferableState(uint256 tokenId, SloplingState state);
    error NotMinter(address caller);
    error SlopPaymentFailed();
    error ZeroAddress();

    event BaseURIUpdated(string baseURI);
    event ContractURIUpdated(string contractURI);
    event Fed(uint256 indexed tokenId, address indexed payer, uint256 periods, uint256 amount, uint256 paidThrough);
    event Immortalized(uint256 indexed tokenId, address indexed payer, uint256 amount);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event Revived(uint256 indexed tokenId, address indexed payer, uint256 amount, uint256 paidThrough);
    event StateBaseURIUpdated(SloplingState indexed state, string baseURI);
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    ISloplingsSlopToken public immutable slopToken;

    address public minter;
    uint256 public totalSupply;
    uint256 public immortalCount;

    mapping(uint256 tokenId => uint256) public paidThrough;
    mapping(uint256 tokenId => bool) public isImmortal;

    string[4] private _stateBaseUris;
    string private _contractUri;

    constructor(
        address owner_,
        address minter_,
        address slopToken_,
        address royaltyReceiver_,
        uint96 royaltyBps_,
        string memory baseUri_,
        string memory starvingBaseUri_,
        string memory deadBaseUri_,
        string memory immortalBaseUri_,
        address transferValidator_
    ) ERC721OpenZeppelin("Sloplings", "SLOPLINGS") {
        if (owner_ == address(0)) {
            revert ZeroAddress();
        }
        if (slopToken_ == address(0)) {
            revert ZeroAddress();
        }

        slopToken = ISloplingsSlopToken(slopToken_);
        _setMinter(minter_);
        _setBaseUri(baseUri_);
        _setStateBaseUri(SloplingState.Starving, starvingBaseUri_);
        _setStateBaseUri(SloplingState.Dead, deadBaseUri_);
        _setStateBaseUri(SloplingState.Immortal, immortalBaseUri_);

        if (royaltyReceiver_ != address(0) || royaltyBps_ != 0) {
            _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
        }

        if (transferValidator_ != address(0) && transferValidator_ != getTransferValidator()) {
            setTransferValidator(transferValidator_);
        }
        if (owner_ != msg.sender) {
            transferOwnership(owner_);
        }
    }

    modifier onlyMinter() {
        if (msg.sender != minter) {
            revert NotMinter(msg.sender);
        }
        _;
    }

    function mint(uint256 tokenId, address recipient) external onlyMinter {
        _validateTokenId(tokenId);
        if (recipient == address(0)) {
            revert ZeroAddress();
        }

        ++totalSupply;
        paidThrough[tokenId] = block.timestamp + FEED_INTERVAL;
        _mint(recipient, tokenId);
    }

    function feed(uint256 tokenId, uint256 periods) external nonReentrant {
        _requireMinted(tokenId);
        if (isImmortal[tokenId]) {
            revert ImmortalSlopling();
        }
        if (periods == 0) {
            revert InvalidFeedPeriods();
        }

        if (stateOf(tokenId) == SloplingState.Dead) {
            revert DeadSlopling();
        }

        uint256 amount = periods * FEED_COST;
        _sendSlopToDead(msg.sender, amount);

        uint256 newPaidThrough = paidThrough[tokenId] + (periods * FEED_INTERVAL);
        paidThrough[tokenId] = newPaidThrough;

        emit Fed(tokenId, msg.sender, periods, amount, newPaidThrough);
        emit MetadataUpdate(tokenId);
    }

    function revive(uint256 tokenId) external nonReentrant {
        _requireMinted(tokenId);
        if (isImmortal[tokenId]) {
            revert ImmortalSlopling();
        }
        if (stateOf(tokenId) != SloplingState.Dead) {
            revert NotDeadSlopling();
        }

        _sendSlopToDead(msg.sender, REVIVE_COST);

        uint256 newPaidThrough = block.timestamp + FEED_INTERVAL;
        paidThrough[tokenId] = newPaidThrough;

        emit Revived(tokenId, msg.sender, REVIVE_COST, newPaidThrough);
        emit MetadataUpdate(tokenId);
    }

    function immortalize(uint256 tokenId) external nonReentrant {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert("ERC721: caller is not token owner or approved");
        }

        if (isImmortal[tokenId]) {
            revert ImmortalSlopling();
        }
        if (stateOf(tokenId) == SloplingState.Dead) {
            revert DeadSlopling();
        }
        if (immortalCount >= MAX_IMMORTAL_SUPPLY) {
            revert ImmortalLimitReached();
        }

        _sendSlopToDead(msg.sender, IMMORTAL_COST);

        isImmortal[tokenId] = true;
        ++immortalCount;

        emit Immortalized(tokenId, msg.sender, IMMORTAL_COST);
        emit MetadataUpdate(tokenId);
    }

    function setMinter(address newMinter) external onlyOwner {
        _setMinter(newMinter);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _setBaseUri(newBaseURI);

        if (totalSupply != 0) {
            emit BatchMetadataUpdate(MIN_TOKEN_ID, MAX_TOKEN_ID);
        }
    }

    function setStateBaseURI(SloplingState state, string calldata newBaseURI) external onlyOwner {
        _setStateBaseUri(state, newBaseURI);

        if (totalSupply != 0) {
            emit BatchMetadataUpdate(MIN_TOKEN_ID, MAX_TOKEN_ID);
        }
    }

    function stateBaseURI(SloplingState state) external view returns (string memory) {
        return _stateBaseUris[uint256(state)];
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        _contractUri = newContractURI;
        emit ContractURIUpdated(newContractURI);
    }

    function contractURI() external view returns (string memory) {
        return _contractUri;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    function stateOf(uint256 tokenId) public view returns (SloplingState) {
        _requireMinted(tokenId);

        if (isImmortal[tokenId]) {
            return SloplingState.Immortal;
        }

        uint256 paid = paidThrough[tokenId];
        if (block.timestamp < paid) {
            return SloplingState.Alive;
        }
        if (block.timestamp < paid + FEED_INTERVAL) {
            return SloplingState.Starving;
        }
        return SloplingState.Dead;
    }

    function feedingPeriodsRequired(uint256 tokenId) public view returns (uint256 periods) {
        _requireMinted(tokenId);

        if (isImmortal[tokenId]) {
            return 0;
        }

        if (stateOf(tokenId) == SloplingState.Dead) {
            return 0;
        }

        uint256 paid = paidThrough[tokenId];
        if (paid > block.timestamp) {
            return 1;
        }

        periods = ((block.timestamp - paid) / FEED_INTERVAL) + 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        SloplingState state = stateOf(tokenId);
        string memory base = _stateBaseUris[uint256(state)];
        return bytes(base).length != 0 ? string.concat(base, tokenId.toString()) : "";
    }

    function emitMetadataUpdate(uint256 tokenId) external onlyOwner {
        _validateTokenId(tokenId);
        emit MetadataUpdate(tokenId);
    }

    function emitBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external onlyOwner {
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721C, ERC2981) returns (bool) {
        return interfaceId == type(ICreatorToken).interfaceId || interfaceId == type(ICreatorTokenLegacy).interfaceId
            || interfaceId == 0x49064906 || super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override(ERC721C)
    {
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < batchSize;) {
                uint256 tokenId = firstTokenId + i;
                SloplingState state = stateOf(tokenId);
                if (state == SloplingState.Starving || state == SloplingState.Dead) {
                    revert NonTransferableState(tokenId, state);
                }

                unchecked {
                    ++i;
                }
            }
        }

        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _setMinter(address newMinter) internal {
        if (newMinter == address(0)) {
            revert ZeroAddress();
        }

        address oldMinter = minter;
        minter = newMinter;
        emit MinterUpdated(oldMinter, newMinter);
    }

    function _setBaseUri(string memory newBaseURI) internal {
        _setStateBaseUri(SloplingState.Alive, newBaseURI);
        emit BaseURIUpdated(newBaseURI);
    }

    function _setStateBaseUri(SloplingState state, string memory newBaseURI) internal {
        _stateBaseUris[uint256(state)] = newBaseURI;
        emit StateBaseURIUpdated(state, newBaseURI);
    }

    function _validateTokenId(uint256 tokenId) internal pure {
        if (tokenId < MIN_TOKEN_ID || tokenId > MAX_TOKEN_ID) {
            revert InvalidTokenId(tokenId);
        }
    }

    function _sendSlopToDead(address payer, uint256 amount) internal {
        if (!slopToken.transferFrom(payer, DEAD_ADDRESS, amount)) {
            revert SlopPaymentFailed();
        }
    }
}
