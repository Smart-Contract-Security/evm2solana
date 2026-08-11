// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Events {
    // Onboarding / rooms
    event InitialRoomPurchased(address indexed player);
    // legacy alias for backwards compat with older indexers
    event InitialFacilityPurchased(address indexed player);

    event FreeMinerRedeemed(address indexed player);

    event RoomUpgraded(address indexed player, uint256 roomIndex, uint256 cost);
    event NewRoomConfigAdded(uint256 roomIndex, uint256 maxMiners, uint256 totalPowerOutput, uint256 cost, bool inProduction, uint256 gridRows, uint256 gridCols, uint256 cooldown);
    event RoomProductionToggled(uint256 roomIndex, bool inProduction);
    event RoomCostChanged(uint256 roomIndex, uint256 newCost);

    // Miners
    event MinerBought(address indexed player, uint256 minerIndex, uint256 cost, uint256 minerId, uint256 row, uint256 col);
    event MinerPlaced(address indexed player, uint256 minerIndex, uint256 cost, uint256 minerId, uint256 row, uint256 col);
    event MinerRemoved(address indexed player, uint256 minerIndex, uint256 cost, uint256 minerId, uint256 row, uint256 col);
    event MinerMoved(address indexed player, uint256 minerId, uint256 fromRow, uint256 fromCol, uint256 toRow, uint256 toCol);
    event NewMinerTemplateAdded(uint256 minerIndex, uint256 hashrate, uint256 energy, uint256 cost, bool inProduction);
    event MinerProductionToggled(uint256 minerIndex, bool inProduction);
    event MinerCostChanged(uint256 minerIndex, uint256 newCost);

    // Hashrate
    event PlayerHashrateIncreased(address indexed player, uint256 hashrate, uint256 pendingRewards);
    event PlayerHashrateDecreased(address indexed player, uint256 hashrate, uint256 pendingRewards);

    // Season / claims
    event SeasonStarted(uint256 seasonStart);
    event RewardsClaimed(address indexed player, uint256 grossMeth, uint256 dMethSide, uint256 methSide, uint8 dMethPercent);

    // Power bill
    event PowerBillAccrued(address indexed player, uint256 accruedTotal);
    event PowerBillPaid(address indexed player, uint256 amount);
    event PowerOutage(address indexed player);
    event PowerRestored(address indexed player);
}
