// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract EcosystemNFT is ERC721, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    uint256 public constant TREASURY_BPS = 100; // 1.00%
    uint256 public constant CREATOR_BPS = 9900; // 99.00%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IERC20 public immutable ect;
    address public immutable treasury;
    uint256 public immutable maxSupply;
    uint256 public immutable mintPrice; // in ECT (18 decimals)

    string private _baseTokenURI;
    uint256 public totalMinted;
    bool public paused;

    event Minted(address indexed buyer, uint256 indexed tokenId, uint256 ectPaid);
    event BaseURIUpdated(string newURI);
    event PausedToggled(bool paused);
    event FeeSplit(address indexed buyer, uint256 toTreasury, uint256 toCreator);

    error SoldOut();
    error Paused();
    error ZeroAmount();
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint256 mintPrice_,
        address creator_,
        address ect_,
        address treasury_
    ) ERC721(name_, symbol_) Ownable(creator_) {
        if (creator_ == address(0) || ect_ == address(0) || treasury_ == address(0)) revert ZeroAddress();
        require(maxSupply_ > 0, "EcosystemNFT: zero maxSupply");
        ect = IERC20(ect_);
        treasury = treasury_;
        maxSupply = maxSupply_;
        mintPrice = mintPrice_;
        _baseTokenURI = baseURI_;
    }

    /// @notice Mint `amount` NFTs to the caller; pays `mintPrice * amount` ECT.
    /// @param amount Number of NFTs to mint.
    function mint(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (paused) revert Paused();
        if (totalMinted + amount > maxSupply) revert SoldOut();

        uint256 totalCost = mintPrice * amount;
        if (totalCost > 0) {
            uint256 toTreasury = (totalCost * TREASURY_BPS) / BPS_DENOMINATOR;
            uint256 toCreator = totalCost - toTreasury;
            ect.safeTransferFrom(msg.sender, address(this), totalCost);
            if (toTreasury > 0) ect.safeTransfer(treasury, toTreasury);
            if (toCreator > 0) ect.safeTransfer(owner(), toCreator);
            emit FeeSplit(msg.sender, toTreasury, toCreator);
        }

        uint256 start = totalMinted;
        unchecked {
            for (uint256 i; i < amount; ++i) {
                _safeMint(msg.sender, start + i);
                emit Minted(msg.sender, start + i, mintPrice);
            }
            totalMinted = start + amount;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata newURI) external onlyOwner {
        _baseTokenURI = newURI;
        emit BaseURIUpdated(newURI);
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedToggled(paused_);
    }
}
