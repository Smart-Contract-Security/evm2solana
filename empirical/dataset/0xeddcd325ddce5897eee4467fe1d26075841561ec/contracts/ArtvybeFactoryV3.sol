// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ArtvybeCollectionV3.sol";

/// @title ArtvybeFactoryV3
/// @notice UUPS-upgradeable factory. Deploys immutable ArtvybeCollectionV3 instances.
contract ArtvybeFactoryV3 is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    uint96 public platformFeeBps;
    address public platformTreasury;

    mapping(address => address[]) public collectionsByCreator;
    address[] public allCollections;

    // Same V1/V2 event signature so existing indexers keep working without
    // a migration. New AL-specific data is emitted as a separate event.
    event CollectionCreated(
        address indexed collection,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply,
        uint96 creatorFeeBps,
        address mintingCurrency,
        uint256 initialMintPrice,
        uint256 mintStartTime
    );

    event CollectionAllowlistConfigured(
        address indexed collection,
        bytes32 merkleRoot,
        uint256 walletLimit,
        uint256 mintPrice,
        uint256 allowlistEnd,
        uint256 publicStart
    );

    event PlatformTreasuryUpdated(address oldTreasury, address newTreasury);
    event PlatformFeeUpdated(uint96 oldFeeBps, uint96 newFeeBps);
    event PlatformPaused(bool paused);

    error InvalidParameters();
    error InvalidMintingCurrency();
    error FeeExceedsMaximum();
    error CollectionCreationFailed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _platformTreasury, address _owner) public initializer {
        if (_platformTreasury == address(0)) revert InvalidParameters();
        if (_owner == address(0)) revert InvalidParameters();
        __Ownable_init(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        platformTreasury = _platformTreasury;
        platformFeeBps = 800;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Backward-compatible entry — deploys a V3 collection with
    ///         allowlist disabled. New frontend calls that don't need the
    ///         allowlist can keep using this signature unchanged.
    function createCollection(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint96 creatorFeeBps,
        address mintingCurrency,
        uint256 initialMintPrice,
        bool batchMintingAllowed,
        string memory baseTokenURI,
        uint256 mintStartTime
    ) external whenNotPaused nonReentrant returns (address) {
        // Disabled-by-default allowlist (no merkle root, public-only mint).
        ArtvybeCollectionV3.AllowlistInit memory empty = ArtvybeCollectionV3.AllowlistInit({
            merkleRoot: bytes32(0),
            enabled: false,
            walletLimit: 0,
            mintPrice: 0,
            allowlistEnd: 0,
            publicStart: 0
        });
        return _deploy(
            name,
            symbol,
            maxSupply,
            creatorFeeBps,
            mintingCurrency,
            initialMintPrice,
            batchMintingAllowed,
            baseTokenURI,
            mintStartTime,
            empty
        );
    }

    /// @notice Deploy a V3 collection with allowlist parameters configured at
    ///         construction time. The allowlist is fully mutable post-deploy
    ///         via owner functions on the resulting collection — the values
    ///         passed here are just the launch defaults.
    function createCollectionWithAllowlist(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint96 creatorFeeBps,
        address mintingCurrency,
        uint256 initialMintPrice,
        bool batchMintingAllowed,
        string memory baseTokenURI,
        uint256 mintStartTime,
        ArtvybeCollectionV3.AllowlistInit memory allowlistInit
    ) external whenNotPaused nonReentrant returns (address) {
        return _deploy(
            name,
            symbol,
            maxSupply,
            creatorFeeBps,
            mintingCurrency,
            initialMintPrice,
            batchMintingAllowed,
            baseTokenURI,
            mintStartTime,
            allowlistInit
        );
    }

    function _deploy(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint96 creatorFeeBps,
        address mintingCurrency,
        uint256 initialMintPrice,
        bool batchMintingAllowed,
        string memory baseTokenURI,
        uint256 mintStartTime,
        ArtvybeCollectionV3.AllowlistInit memory allowlistInit
    ) internal returns (address) {
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert InvalidParameters();
        if (bytes(name).length > 50 || bytes(symbol).length > 20) revert InvalidParameters();
        if (maxSupply == 0) revert InvalidParameters();
        if (creatorFeeBps > 1000) revert FeeExceedsMaximum();
        if (creatorFeeBps + platformFeeBps > 10000) revert FeeExceedsMaximum();
        if (mintStartTime < block.timestamp) revert InvalidParameters();

        if (mintingCurrency != address(0)) {
            // Smoke test: any contract that responds to a static totalSupply()
            // call is considered ERC20-like for the purpose of pricing mints.
            // A zero supply almost certainly indicates a misconfigured or
            // brand-new token; reject so creators can't accidentally launch
            // against an empty currency.
            try IERC20(mintingCurrency).totalSupply() returns (uint256 supply) {
                if (supply == 0) revert InvalidMintingCurrency();
            } catch {
                revert InvalidMintingCurrency();
            }
        }

        ArtvybeCollectionV3 collection = new ArtvybeCollectionV3(
            name,
            symbol,
            maxSupply,
            creatorFeeBps,
            mintingCurrency,
            initialMintPrice,
            batchMintingAllowed,
            baseTokenURI,
            msg.sender,
            platformTreasury,
            platformFeeBps,
            mintStartTime,
            allowlistInit
        );

        address collectionAddress = address(collection);

        collectionsByCreator[msg.sender].push(collectionAddress);
        allCollections.push(collectionAddress);

        emit CollectionCreated(
            collectionAddress,
            msg.sender,
            name,
            symbol,
            maxSupply,
            creatorFeeBps,
            mintingCurrency,
            initialMintPrice,
            mintStartTime
        );

        if (allowlistInit.merkleRoot != bytes32(0) || allowlistInit.enabled) {
            emit CollectionAllowlistConfigured(
                collectionAddress,
                allowlistInit.merkleRoot,
                allowlistInit.walletLimit,
                allowlistInit.mintPrice,
                allowlistInit.allowlistEnd,
                allowlistInit.publicStart
            );
        }

        return collectionAddress;
    }

    function getCollectionsByCreator(address creator) external view returns (address[] memory) {
        return collectionsByCreator[creator];
    }

    function getAllCollections() external view returns (address[] memory) {
        return allCollections;
    }

    function getCreatorCollectionCount(address creator) external view returns (uint256) {
        return collectionsByCreator[creator].length;
    }

    function getTotalCollectionCount() external view returns (uint256) {
        return allCollections.length;
    }

    function setPlatformTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidParameters();
        address oldTreasury = platformTreasury;
        platformTreasury = newTreasury;
        emit PlatformTreasuryUpdated(oldTreasury, newTreasury);
    }

    function setPlatformFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > 1000) revert FeeExceedsMaximum();
        uint96 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFeeBps, newFeeBps);
    }

    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
        emit PlatformPaused(paused);
    }

    function version() external pure returns (string memory) {
        return "v3";
    }

    function recoverTokens(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidParameters();
        IERC20(token).safeTransfer(to, amount);
    }

    function recoverETH(address to) external onlyOwner {
        if (to == address(0)) revert InvalidParameters();
        (bool success, ) = to.call{value: address(this).balance}("");
        if (!success) revert CollectionCreationFailed();
    }

    receive() external payable {}

    /// @dev Reserved storage gap for future upgrades.
    uint256[45] private __gap;
}
