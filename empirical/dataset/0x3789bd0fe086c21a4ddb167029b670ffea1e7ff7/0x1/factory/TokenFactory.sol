// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IECT, IECTBurnable} from "../interfaces/IECT.sol";
import {ITokenFactory} from "../interfaces/ITokenFactory.sol";
import {IEcosystemRegistry} from "../interfaces/IEcosystemRegistry.sol";
import {IECTPairFactory} from "../interfaces/IECTPairFactory.sol";

import {CreatedToken} from "./CreatedToken.sol";

contract TokenFactory is ReentrancyGuard, ITokenFactory {
    using SafeERC20 for IERC20;

    uint256 public constant override LAUNCH_FEE = 1000 ether;
    uint256 public constant TREASURY_BPS = 200;  // 2%
    uint256 public constant BURN_BPS = 9800;     // 98%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IECT public immutable ectToken;
    address public immutable override treasury;
    IEcosystemRegistry public immutable registryRef;
    IECTPairFactory public immutable pairFactoryRef;

    error InvalidSupply();
    error ZeroAddress();

    constructor(address ect_, address treasury_, address registry_, address pairFactory_) {
        if (ect_ == address(0) || treasury_ == address(0) || registry_ == address(0)
            || pairFactory_ == address(0)) revert ZeroAddress();
        ectToken = IECT(ect_);
        treasury = treasury_;
        registryRef = IEcosystemRegistry(registry_);
        pairFactoryRef = IECTPairFactory(pairFactory_);
    }

    function ect() external view override returns (address) { return address(ectToken); }
    function registry() external view override returns (address) { return address(registryRef); }
    function pairFactory() external view override returns (address) { return address(pairFactoryRef); }

    /// @inheritdoc ITokenFactory
    function createToken(string calldata name, string calldata symbol, uint256 supply)
        external
        override
        nonReentrant
        returns (address token)
    {
        if (supply == 0) revert InvalidSupply();

        uint256 toTreasury = (LAUNCH_FEE * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 toBurn = LAUNCH_FEE - toTreasury;

        IERC20(address(ectToken)).safeTransferFrom(msg.sender, address(this), LAUNCH_FEE);
        IERC20(address(ectToken)).safeTransfer(treasury, toTreasury);
        IECTBurnable(address(ectToken)).burn(toBurn);

        token = address(new CreatedToken(name, symbol, supply, msg.sender));

        registryRef.registerToken(token, msg.sender, name, symbol, supply);
        pairFactoryRef.registerTokenCreator(token, msg.sender);

        emit TokenCreated(token, msg.sender, name, symbol, supply);
    }
}
