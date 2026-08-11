// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IECTPairFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256 allPairsLength,
        address indexed creator
    );

    function ect() external view returns (address);
    function treasury() external view returns (address);
    function PAIR_CREATION_FEE() external view returns (uint256);

    function getPair(address tokenA, address tokenB) external view returns (address);
    function allPairs(uint256) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function isPair(address) external view returns (bool);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    /// @notice Registered creator of the non-ECT side; address(0) if unregistered.
    function tokenCreator(address token) external view returns (address);

    /// @notice Updates the creator-fee recipient on the token's ECT pair.
    function setCreatorRecipient(address token, address newRecipient) external;

    /// @notice Registers the creator of a token. Callable only by the TokenFactory.
    function registerTokenCreator(address token, address creator) external;

    function tokenFactory() external view returns (address);
    function setTokenFactory(address _tokenFactory) external;
}
