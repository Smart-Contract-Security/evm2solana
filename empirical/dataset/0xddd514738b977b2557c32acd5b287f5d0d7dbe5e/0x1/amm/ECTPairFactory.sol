// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ECTPair} from "./ECTPair.sol";
import {IECTPair} from "../interfaces/IECTPair.sol";
import {IECTPairFactory} from "../interfaces/IECTPairFactory.sol";

contract ECTPairFactory is Ownable2Step, IECTPairFactory {
    using SafeERC20 for IERC20;

    address public immutable override ect;
    address public immutable override treasury;

    uint256 public constant override PAIR_CREATION_FEE = 100 ether;

    address public override tokenFactory;

    mapping(address => mapping(address => address)) private _getPair;
    address[] public override allPairs;
    mapping(address => bool) public override isPair;

    mapping(address => address) public override tokenCreator;

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error MustIncludeECT();
    error NotTokenFactory();
    error NotTokenCreator();
    error AlreadyWired();

    constructor(address initialOwner, address ect_, address treasury_) Ownable(initialOwner) {
        if (initialOwner == address(0) || ect_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        ect = ect_;
        treasury = treasury_;
    }

    /// @notice One-shot wire-up of the TokenFactory. Reverts on subsequent calls.
    function setTokenFactory(address _tokenFactory) external override onlyOwner {
        if (tokenFactory != address(0)) revert AlreadyWired();
        if (_tokenFactory == address(0)) revert ZeroAddress();
        tokenFactory = _tokenFactory;
    }

    /// @inheritdoc IECTPairFactory
    function getPair(address tokenA, address tokenB) external view override returns (address) {
        return _getPair[tokenA][tokenB];
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    /// @inheritdoc IECTPairFactory
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        if (tokenA != ect && tokenB != ect) revert MustIncludeECT();
        if (tokenA == tokenB) revert IdenticalAddresses();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (_getPair[token0][token1] != address(0)) revert PairExists();

        IERC20(ect).safeTransferFrom(msg.sender, treasury, PAIR_CREATION_FEE);

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new ECTPair{salt: salt}());
        IECTPair(pair).initialize(token0, token1, treasury);

        _getPair[token0][token1] = pair;
        _getPair[token1][token0] = pair;
        allPairs.push(pair);
        isPair[pair] = true;

        emit PairCreated(token0, token1, pair, allPairs.length, msg.sender);
    }

    /// @inheritdoc IECTPairFactory
    function registerTokenCreator(address token, address creator) external override {
        if (msg.sender != tokenFactory) revert NotTokenFactory();
        // First-registration wins; subsequent calls are no-ops.
        if (tokenCreator[token] == address(0)) tokenCreator[token] = creator;
    }

    /// @inheritdoc IECTPairFactory
    function setCreatorRecipient(address token, address newRecipient) external override {
        if (token == ect) revert MustIncludeECT();
        if (tokenCreator[token] != msg.sender) revert NotTokenCreator();

        address sortedToken0 = token < ect ? token : ect;
        address sortedToken1 = token < ect ? ect : token;
        address pair = _getPair[sortedToken0][sortedToken1];
        require(pair != address(0), "Factory: pair not created");
        IECTPair(pair).setCreatorRecipient(newRecipient);
    }
}
