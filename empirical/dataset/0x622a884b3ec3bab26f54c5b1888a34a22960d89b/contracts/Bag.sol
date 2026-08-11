// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IDMethMint {
    function mint(address to, uint256 amount) external;
}

/**
 * @title Bag
 * @notice Soulbound Bag NFT holding a fixed dMETH allocation. Cannot be traded.
 * Players must wait 3 days from mint before redemption. Redemption pays out 97%
 * of the gross dMETH to the holder; the remaining 3% is voided (never minted).
 */
contract Bag is ERC721, Ownable {
    struct BagData {
        uint128 grossDmethAmount;
        uint64 createdAt;
        uint64 unlockAt;
        bool redeemed;
    }

    uint256 public constant WAIT_DURATION = 3 days;
    uint256 public constant PAYOUT_RATE = 0.90e18; // 90%
    uint256 public constant RATE_PRECISION = 1e18;

    address public miningSystem;
    address public dmeth;

    uint256 private _tokenIdCounter;
    mapping(uint256 => BagData) public bags;

    event BagMinted(uint256 indexed tokenId, address indexed to, uint256 grossDmethAmount, uint256 unlockAt);
    event BagRedeemed(uint256 indexed tokenId, address indexed holder, uint256 payout, uint256 burned);
    event MiningSystemUpdated(address indexed miningSystem);
    event DMethUpdated(address indexed dmeth);

    error OnlyMiningSystem();
    error BagNotFound();
    error AlreadyRedeemed();
    error NotUnlocked();
    error SoulboundTransferDenied();
    error NotHolder();
    error ZeroAddress();

    constructor() ERC721("METH Bag", "BAG") Ownable(msg.sender) {}

    modifier onlyMiningSystem() {
        if (msg.sender != miningSystem) revert OnlyMiningSystem();
        _;
    }

    function mintBag(address to, uint256 grossDmethAmount) external onlyMiningSystem returns (uint256) {
        if (grossDmethAmount == 0) return 0;
        uint256 tokenId = ++_tokenIdCounter;
        _safeMint(to, tokenId);
        uint64 unlockAt = uint64(block.timestamp + WAIT_DURATION);
        bags[tokenId] = BagData({
            grossDmethAmount: uint128(grossDmethAmount),
            createdAt: uint64(block.timestamp),
            unlockAt: unlockAt,
            redeemed: false
        });
        emit BagMinted(tokenId, to, grossDmethAmount, unlockAt);
        return tokenId;
    }

    function redeem(uint256 tokenId) external {
        address holder = _ownerOf(tokenId);
        if (holder == address(0)) revert BagNotFound();
        if (holder != msg.sender) revert NotHolder();

        BagData storage data = bags[tokenId];
        if (data.redeemed) revert AlreadyRedeemed();
        if (block.timestamp < data.unlockAt) revert NotUnlocked();

        uint256 gross = data.grossDmethAmount;
        uint256 payout = (gross * PAYOUT_RATE) / RATE_PRECISION;
        uint256 burned = gross - payout;

        data.redeemed = true;
        _burn(tokenId);

        if (payout > 0) {
            IDMethMint(dmeth).mint(holder, payout);
        }
        // Burned portion is never minted, satisfying the 10% tax.

        emit BagRedeemed(tokenId, holder, payout, burned);
    }

    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    // Block all peer-to-peer transfers. Mint (from==0) and burn (to==0) are still allowed.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert SoulboundTransferDenied();
        }
        return super._update(to, tokenId, auth);
    }

    function setMiningSystem(address _miningSystem) external onlyOwner {
        if (_miningSystem == address(0)) revert ZeroAddress();
        miningSystem = _miningSystem;
        emit MiningSystemUpdated(_miningSystem);
    }

    function setDMeth(address _dmeth) external onlyOwner {
        if (_dmeth == address(0)) revert ZeroAddress();
        dmeth = _dmeth;
        emit DMethUpdated(_dmeth);
    }
}
