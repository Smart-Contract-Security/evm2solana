// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBondingCurve {
    event Minted(address indexed buyer, uint256 amount, uint256 ethPaid, uint256 newSold);
    event CurveClosed(uint256 totalEthRaised);
    event TreasuryWithdrawal(address indexed to, uint256 amount);

    function mint(uint256 amount) external payable;
    function sellBack(uint256 amount) external;

    function quoteBuy(uint256 amount) external view returns (uint256 ethCost);
    function quoteSell(uint256 amount) external view returns (uint256 ethReturn);

    function curveProgress()
        external
        view
        returns (uint256 soldSoFar, uint256 ethRaisedSoFar, uint256 percentComplete);

    function withdrawToTreasury() external;

    function MAX_SUPPLY() external view returns (uint256);
    function MAX_MINT_PER_TX() external view returns (uint256);
    function TARGET_ETH() external view returns (uint256);
    function curveClosed() external view returns (bool);
}
