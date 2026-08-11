// SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ITermRepoToken is IERC20 {
    function redemptionValue() external view returns (uint256);

    function totalRedemptionValue() external view returns (uint256);

    function burn(address account, uint256 amount) external;

    function burnAndReturnValue(
        address account,
        uint256 amount
    ) external returns (uint256);

    function mintRedemptionValue(
        address account,
        uint256 redemptionAmount
    ) external returns (uint256);

    function mintTokens(
        address account,
        uint256 numTokens
    ) external returns (uint256);

    function decrementMintExposureCap(uint256 supplyMinted) external;
}