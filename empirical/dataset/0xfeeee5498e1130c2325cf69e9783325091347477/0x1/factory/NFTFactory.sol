// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IECT, IECTBurnable} from "../interfaces/IECT.sol";
import {INFTFactory} from "../interfaces/INFTFactory.sol";
import {IEcosystemRegistry} from "../interfaces/IEcosystemRegistry.sol";

import {EcosystemNFT} from "../nft/EcosystemNFT.sol";

contract NFTFactory is ReentrancyGuard, INFTFactory {
    using SafeERC20 for IERC20;

    uint256 public constant override LAUNCH_FEE = 500 ether;
    uint256 public constant TREASURY_BPS = 200;  // 2%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IECT public immutable ectToken;
    address public immutable override treasury;
    IEcosystemRegistry public immutable registryRef;

    error ZeroAddress();
    error InvalidMaxSupply();

    constructor(address ect_, address treasury_, address registry_) {
        if (ect_ == address(0) || treasury_ == address(0) || registry_ == address(0)) revert ZeroAddress();
        ectToken = IECT(ect_);
        treasury = treasury_;
        registryRef = IEcosystemRegistry(registry_);
    }

    function ect() external view override returns (address) { return address(ectToken); }
    function registry() external view override returns (address) { return address(registryRef); }

    /// @inheritdoc INFTFactory
    function createCollection(
        string calldata name,
        string calldata symbol,
        string calldata baseURI,
        uint256 maxSupply,
        uint256 mintPrice
    ) external override nonReentrant returns (address collection) {
        if (maxSupply == 0) revert InvalidMaxSupply();

        uint256 toTreasury = (LAUNCH_FEE * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 toBurn = LAUNCH_FEE - toTreasury;

        IERC20(address(ectToken)).safeTransferFrom(msg.sender, address(this), LAUNCH_FEE);
        IERC20(address(ectToken)).safeTransfer(treasury, toTreasury);
        IECTBurnable(address(ectToken)).burn(toBurn);

        collection = address(new EcosystemNFT(
            name, symbol, baseURI, maxSupply, mintPrice, msg.sender, address(ectToken), treasury
        ));

        registryRef.registerCollection(collection, msg.sender, name, symbol, maxSupply, mintPrice);
        emit CollectionCreated(collection, msg.sender, name, symbol, maxSupply, mintPrice);
    }
}
