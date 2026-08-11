// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSetLib} from "solady/src/utils/EnumerableSetLib.sol";

import {IDMeth} from "../interfaces/IDMeth.sol";
import {ICheck} from "../interfaces/ICheck.sol";
import {IBag} from "../interfaces/IBag.sol";

import {Miner} from "../types/Miner.sol";
import {Room} from "../types/Room.sol";
import {RoomConfig} from "../types/RoomConfig.sol";
import {PowerBillState} from "../types/PowerBillState.sol";

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";

interface IMinerNFT is IERC721 {
    function mintMinerNFT(address to, uint32 minerId, uint8 minerIndex, uint32 hashrate, uint32 powerConsumption) external returns (uint256);
    function getMinerData(uint256 tokenId) external view returns (uint32 minerId, uint8 minerIndex, uint32 hashrate, uint32 powerConsumption);
    function burn(uint256 tokenId) external;
}

/**
 * @title MiningEthSystem
 * @notice Season 1 game engine for Mining ETH. Implements rooms, grid placement,
 * miners, per-second power bills with a 24-hour rolling timer, fixed monthly
 * METH emissions, and claim-time splits into Check (METH) and Bag (dMETH)
 * instruments. dMETH is the in-game currency consumed by purchases and bills.
 * METH is only ever emitted into circulation via Check redemption.
 */
contract MiningEthSystem is Ownable, ReentrancyGuard {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    struct MinerTemplate {
        uint32 hashrate;
        uint32 energy;
        uint256 cost;       // dMETH wei
        bool inProduction;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            STORAGE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    address public meth;
    address public dmeth;
    address public minerNFT;
    address public checkNFT;
    address public bagNFT;
    address public tokenDistribution;
    address public treasury;

    // Season timing.
    uint256 public seasonStart;
    bool public seasonStarted;
    uint256 public constant SEASON_LENGTH = 90 days;
    uint256 public constant MONTH_LENGTH = 30 days;

    // METH emissions per second by month, in wei. Integer division truncates a tiny
    // fraction; this is acceptable and matches the spec at the second granularity.
    uint256 public constant METH_PER_SEC_M1 = uint256(180_000e18) / 86_400; // ~2.0833e18
    uint256 public constant METH_PER_SEC_M2 = uint256( 90_000e18) / 86_400; // ~1.0417e18
    uint256 public constant METH_PER_SEC_M3 = uint256( 45_000e18) / 86_400; // ~0.5208e18

    // Reward accumulator. Uses block.timestamp throughout.
    uint256 public lastRewardTimestamp;
    uint256 public totalEligibleHash;
    uint256 public cumulativeMethPerHash;
    uint256 public constant REWARDS_PRECISION = 1e18;

    // Player reward state. `playerEligibleHashrate` is what contributes to
    // totalEligibleHash; it goes to zero during a power outage. `playerStoredHashrate`
    // remembers the player's full equipped hash so we can restore on payment.
    mapping(address => uint256) public playerEligibleHashrate;
    mapping(address => uint256) public playerStoredHashrate;
    mapping(address => uint256) public playerPendingMethRewards;
    mapping(address => uint256) public playerMethDebt;

    // track players last claim to enforce claim cooldown
    mapping(address => uint256) public playerLastClaim;
    uint256 public playerClaimCooldown = 8 hours;

    // Room registry.
    uint8 public roomConfigCount;
    mapping(uint256 => RoomConfig) public roomConfigs;
    mapping(address => Room) public ownerToRoom;
    mapping(address => PowerBillState) public ownerToBill;
    mapping(address => bool) public initializedStarterRoom;
    mapping(address => uint256) public lastRoomUpgradeTimestamp;

    // Miner registry.
    uint8 public uniqueMinerCount;
    uint32 public universalMinerId;
    mapping(uint256 => MinerTemplate) public minerTemplates;
    mapping(uint256 => Miner) public playerMinersId;
    mapping(address => EnumerableSetLib.Uint256Set) playerMinersOwned;
    mapping(address => mapping(uint8 => mapping(uint8 => bool))) public playerOccupiedCoords;
    mapping(uint32 => uint256) public minerToNFT;
    mapping(uint256 => uint32) public nftToMiner;
    mapping(address => bool) public starterMinerAcquired;

    // Addresses authorized to reserve minerIds against universalMinerId (e.g. Packs).
    mapping(address => bool) public authorizedMinerIdReservers;

    uint8 public immutable STARTER_MINER_INDEX;
    uint8 public immutable STARTER_ROOM_INDEX;

    // Initial room price (ETH) for Trap House activation.
    uint256 public initialRoomPrice = 0.01 ether;

    // Power-bill rate. debt_per_second (wei) = (energy * 3e18) / 8_640_000.
    uint256 public constant BILL_NUMERATOR = 3e18;
    uint256 public constant BILL_DENOMINATOR = 8_640_000;
    uint256 public constant BILL_WINDOW = 24 hours;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //          CONSTRUCTOR
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @dev Seeds the starter miner (McHash) and the starter room (Trap House).
    /// Additional miners and rooms are added by the owner via the admin functions.
    constructor() Ownable(msg.sender) {
        // Miner 1: McHash — hashrate 100, energy 1, free.
        ++uniqueMinerCount;
        STARTER_MINER_INDEX = uniqueMinerCount;
        minerTemplates[STARTER_MINER_INDEX] = MinerTemplate({
            hashrate: 100,
            energy: 1,
            cost: 0,
            inProduction: false // free; not directly purchasable
        });

        // Room 1: Trap House — 2x2 grid, 20 power, paid in ETH (cost field is 0).
        ++roomConfigCount;
        STARTER_ROOM_INDEX = roomConfigCount;
        roomConfigs[STARTER_ROOM_INDEX] = RoomConfig({
            maxMiners: 4,
            totalPowerOutput: 20,
            cost: 0,
            inProduction: true,
            gridRows: 2,
            gridCols: 2,
            cooldown: 24 hours
        });
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        USER FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Activate the starter room (Trap House) with the initial ETH purchase.
    function purchaseInitialRoom() external payable nonReentrant {
        if (msg.value != initialRoomPrice) revert Errors.IncorrectValue();
        if (initializedStarterRoom[msg.sender]) revert Errors.AlreadyPurchasedInitialFactory();

        initializedStarterRoom[msg.sender] = true;
        RoomConfig memory cfg = roomConfigs[STARTER_ROOM_INDEX];
        Room storage r = ownerToRoom[msg.sender];
        r.roomIndex = STARTER_ROOM_INDEX;
        r.maxMiners = cfg.maxMiners;
        r.totalPowerOutput = cfg.totalPowerOutput;
        r.gridRows = cfg.gridRows;
        r.gridCols = cfg.gridCols;
        // Trap House has no power bill; we leave PowerBillState zero-initialized.

        emit Events.InitialRoomPurchased(msg.sender);
        emit Events.InitialFacilityPurchased(msg.sender);
    }

    /// @notice Place the free starter miner (McHash) on the grid. One per wallet.
    function getFreeStarterMiner(uint8 row, uint8 col) external {
        if (!initializedStarterRoom[msg.sender]) revert Errors.NeedToInitializeFacility();
        if (starterMinerAcquired[msg.sender]) revert Errors.StarterMinerAlreadyAcquired();
        starterMinerAcquired[msg.sender] = true;

        MinerTemplate memory tmpl = minerTemplates[STARTER_MINER_INDEX];
        _placeNewMiner(msg.sender, STARTER_MINER_INDEX, tmpl.hashrate, tmpl.energy, row, col, 0);
        emit Events.FreeMinerRedeemed(msg.sender);
    }

    /// @notice Buy a new miner with dMETH and place it on the grid.
    function buyMiner(uint8 minerIndex, uint8 row, uint8 col) external {
        if (minerIndex == 0 || minerIndex > uniqueMinerCount) revert Errors.InvalidMinerIndex();
        if (minerIndex == STARTER_MINER_INDEX) revert Errors.MinerNotInProduction();

        MinerTemplate memory tmpl = minerTemplates[minerIndex];
        if (!tmpl.inProduction) revert Errors.MinerNotInProduction();
        if (IDMeth(dmeth).balanceOf(msg.sender) < tmpl.cost) revert Errors.TooPoor();

        // Burn dMETH cost.
        IDMeth(dmeth).burn(msg.sender, tmpl.cost);

        _placeNewMiner(msg.sender, minerIndex, tmpl.hashrate, tmpl.energy, row, col, tmpl.cost);
    }

    /// @notice Place a miner NFT held by the user into their active room.
    function placeMiner(uint256 nftTokenId, uint8 row, uint8 col) external nonReentrant {
        if (IMinerNFT(minerNFT).ownerOf(nftTokenId) != msg.sender) revert Errors.PlayerDoesNotOwnMiner();

        (uint32 minerId, uint8 minerIndex, uint32 hashrate, uint32 powerConsumption) =
            IMinerNFT(minerNFT).getMinerData(nftTokenId);

        Room storage room = ownerToRoom[msg.sender];
        if (room.roomIndex == 0) revert Errors.NeedToInitializeFacility();
        if (_isInvalidCoordinates(msg.sender, row, col, room.gridRows, room.gridCols)) {
            revert Errors.InvalidMinerCoordinates();
        }

        _settleBill(msg.sender);
        _checkOutage(msg.sender);

        if (uint256(room.currPowerOutput) + powerConsumption > uint256(room.totalPowerOutput)) {
            revert Errors.FacilityInadequatePowerOutput();
        }
        if (room.currMiners >= room.maxMiners) revert Errors.MinerCapacityReached();

        IMinerNFT(minerNFT).transferFrom(msg.sender, address(this), nftTokenId);

        Miner memory miner = Miner({
            minerIndex: minerIndex,
            x: row,
            y: col,
            id: minerId,
            hashrate: hashrate,
            powerConsumption: powerConsumption,
            cost: minerTemplates[minerIndex].cost,
            inProduction: minerTemplates[minerIndex].inProduction
        });

        playerOccupiedCoords[msg.sender][row][col] = true;
        playerMinersOwned[msg.sender].add(minerId);
        playerMinersId[minerId] = miner;
        nftToMiner[nftTokenId] = minerId;

        // If its a pack rolled NFT we must set here 
        if(minerToNFT[minerId] == 0) {
            minerToNFT[minerId] = nftTokenId;
        }

        room.currMiners++;
        room.currPowerOutput += powerConsumption;

        emit Events.MinerPlaced(msg.sender, minerIndex, 0, minerId, row, col);

        _gainHashrate(msg.sender, hashrate);
    }

    /// @notice Remove a miner from the grid. Returns the miner to the player as an NFT.
    function removeMiner(uint32 minerId) external nonReentrant {
        if (!playerMinersOwned[msg.sender].contains(minerId)) revert Errors.PlayerDoesNotOwnMiner();

        Miner memory miner = playerMinersId[minerId];
        Room storage room = ownerToRoom[msg.sender];

        _settleBill(msg.sender);
        _checkOutage(msg.sender);

        room.currMiners--;
        room.currPowerOutput -= miner.powerConsumption;

        playerMinersOwned[msg.sender].remove(minerId);
        delete playerMinersId[minerId];
        playerOccupiedCoords[msg.sender][miner.x][miner.y] = false;

        emit Events.MinerRemoved(msg.sender, miner.minerIndex, 0, minerId, miner.x, miner.y);

        _loseHashrate(msg.sender, miner.hashrate);

        uint256 nftTokenId = minerToNFT[minerId];
        if (nftTokenId != 0) {
            IMinerNFT(minerNFT).transferFrom(address(this), msg.sender, nftTokenId);
            delete nftToMiner[nftTokenId];
        } else {
            nftTokenId = IMinerNFT(minerNFT).mintMinerNFT(
                msg.sender,
                minerId,
                miner.minerIndex,
                miner.hashrate,
                miner.powerConsumption
            );
            minerToNFT[minerId] = nftTokenId;
        }
    }

    /// @notice Move a placed miner to a different empty slot in the same room.
    /// Energy total does not change; bill settlement still snapshots to keep
    /// timestamps tidy.
    function moveMiner(uint32 minerId, uint8 newRow, uint8 newCol) external {
        if (!playerMinersOwned[msg.sender].contains(minerId)) revert Errors.PlayerDoesNotOwnMiner();
        Miner storage miner = playerMinersId[minerId];
        Room storage room = ownerToRoom[msg.sender];

        if (newRow >= room.gridRows || newCol >= room.gridCols) revert Errors.InvalidMinerCoordinates();
        if (playerOccupiedCoords[msg.sender][newRow][newCol]) revert Errors.InvalidMinerCoordinates();

        _settleBill(msg.sender);

        uint8 fromRow = miner.x;
        uint8 fromCol = miner.y;
        playerOccupiedCoords[msg.sender][fromRow][fromCol] = false;
        playerOccupiedCoords[msg.sender][newRow][newCol] = true;
        miner.x = newRow;
        miner.y = newCol;

        emit Events.MinerMoved(msg.sender, minerId, fromRow, fromCol, newRow, newCol);
    }

    /// @notice Upgrade to the next room. Costs dMETH. Cooldown is enforced.
    /// Power-bill state is initialized when the wallet first enters room 2+.
    function buyNewRoom() external {
        if (!initializedStarterRoom[msg.sender]) revert Errors.NeedToInitializeFacility();

        Room storage currRoom = ownerToRoom[msg.sender];
        uint256 currIdx = currRoom.roomIndex;
        if (currIdx == roomConfigCount) revert Errors.AlreadyAtMaxFacility();

        RoomConfig memory next = roomConfigs[currIdx + 1];
        if (!next.inProduction) revert Errors.NewFacilityNotInProduction();

        // Cooldown is enforced against the cooldown of the room being entered.
        uint256 last = lastRoomUpgradeTimestamp[msg.sender];
        if (last != 0 && block.timestamp - last < next.cooldown) revert Errors.CantBuyNewFacilityYet();

        if (IDMeth(dmeth).balanceOf(msg.sender) < next.cost) revert Errors.TooPoor();
        if (next.cost > 0) {
            IDMeth(dmeth).burn(msg.sender, next.cost);
        }

        // Settle current bill before mutating room (in case currIdx >= 2).
        _settleBill(msg.sender);
        _checkOutage(msg.sender);

        currRoom.roomIndex = uint8(currIdx + 1);
        currRoom.maxMiners = next.maxMiners;
        currRoom.totalPowerOutput = next.totalPowerOutput;
        currRoom.gridRows = next.gridRows;
        currRoom.gridCols = next.gridCols;
        // currPowerOutput and currMiners carry over from the previous room.

        lastRoomUpgradeTimestamp[msg.sender] = block.timestamp;

        // If we just entered the bill regime (room 2+) from a state where the bill
        // was never initialized, start a fresh 24h window now.
        PowerBillState storage bill = ownerToBill[msg.sender];
        if (currRoom.roomIndex >= 2 && bill.billLastSettlementTimestamp == 0) {
            bill.billLastSettlementTimestamp = uint64(block.timestamp);
            bill.billWindowStart = uint64(block.timestamp);
            bill.billWindowEnd = uint64(block.timestamp + BILL_WINDOW);
            bill.billDebtAccrued = 0;
            bill.powerOffline = false;
        }

        emit Events.RoomUpgraded(msg.sender, currRoom.roomIndex, next.cost);
    }

    /// @notice Pay the current accrued power bill. Resets the 24h window. If the
    /// room was offline, payment restores power and the player's hashrate
    /// re-enters the eligible pool.
    function payPowerBill() external {
        Room storage room = ownerToRoom[msg.sender];
        if (room.roomIndex < 2) revert Errors.NoPowerBill();

        _settleBill(msg.sender);

        PowerBillState storage bill = ownerToBill[msg.sender];
        uint256 debt = bill.billDebtAccrued;
        if (debt == 0) revert Errors.NoBillDue();

        if (IDMeth(dmeth).balanceOf(msg.sender) < debt) revert Errors.TooPoor();
        IDMeth(dmeth).burn(msg.sender, debt);

        bool wasOffline = bill.powerOffline;

        bill.billDebtAccrued = 0;
        bill.billWindowStart = uint64(block.timestamp);
        bill.billWindowEnd = uint64(block.timestamp + BILL_WINDOW);
        bill.billLastSettlementTimestamp = uint64(block.timestamp);

        if (wasOffline) {
            bill.powerOffline = false;
            uint256 stored = playerStoredHashrate[msg.sender];
            if (stored > 0) {
                _updateRewards(msg.sender);
                totalEligibleHash += stored;
                playerEligibleHashrate[msg.sender] = stored;
                playerMethDebt[msg.sender] = cumulativeMethPerHash;
                emit Events.PlayerHashrateIncreased(msg.sender, stored, playerPendingMethRewards[msg.sender]);
            }
            emit Events.PowerRestored(msg.sender);
        }

        emit Events.PowerBillPaid(msg.sender, debt);
    }

    /// @notice Claim accumulated rewards. Splits the gross METH-denominated
    /// reward into a Check (METH side) and Bag (dMETH side). `dMethPercent`
    /// must be a multiple of 10 in [0, 80].
    function claimRewards(uint8 dMethPercent) external nonReentrant {
        if (!initializedStarterRoom[msg.sender]) revert Errors.NeedToInitializeFacility();
        if (isPlayerOnClaimCooldown(msg.sender)) revert Errors.PlayerOnClaimCooldown();
        if (dMethPercent > 80 || dMethPercent % 10 != 0) revert Errors.InvalidClaimSplit();

        _settleBill(msg.sender);
        _checkOutage(msg.sender);
        _updateRewards(msg.sender);

        uint256 gross = playerPendingMethRewards[msg.sender];
        if (gross == 0) revert Errors.NoRewardsPending();

        playerPendingMethRewards[msg.sender] = 0;
        playerLastClaim[msg.sender] = block.timestamp;

        uint256 dMethSide = (gross * dMethPercent) / 100;
        uint256 methSide = gross - dMethSide;

        if (methSide > 0) {
            ICheck(checkNFT).mintCheck(msg.sender, methSide);
        }
        if (dMethSide > 0) {
            IBag(bagNFT).mintBag(msg.sender, dMethSide);
        }

        emit Events.RewardsClaimed(msg.sender, gross, dMethSide, methSide, dMethPercent);
    }

    /// @notice Anyone may force-mark a stale unpaid wallet as offline. This
    /// removes their hashrate from the eligible pool, raising every other
    /// active miner's share. Useful as a keeper hook.
    function markOffline(address player) external {
        _settleBill(player);
        _checkOutage(player);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //       INTERNAL FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function _placeNewMiner(
        address player,
        uint8 minerIndex,
        uint32 hashrate,
        uint32 energy,
        uint8 row,
        uint8 col,
        uint256 cost
    ) internal {
        Room storage room = ownerToRoom[player];
        if (room.roomIndex == 0) revert Errors.NeedToInitializeFacility();
        if (_isInvalidCoordinates(player, row, col, room.gridRows, room.gridCols)) {
            revert Errors.InvalidMinerCoordinates();
        }

        _settleBill(player);
        _checkOutage(player);

        if (uint256(room.currPowerOutput) + energy > uint256(room.totalPowerOutput)) {
            revert Errors.FacilityInadequatePowerOutput();
        }
        if (room.currMiners >= room.maxMiners) revert Errors.MinerCapacityReached();

        ++universalMinerId;
        Miner memory miner = Miner({
            minerIndex: minerIndex,
            x: row,
            y: col,
            id: universalMinerId,
            hashrate: hashrate,
            powerConsumption: energy,
            cost: cost,
            inProduction: minerTemplates[minerIndex].inProduction
        });

        playerOccupiedCoords[player][row][col] = true;
        playerMinersOwned[player].add(universalMinerId);
        playerMinersId[universalMinerId] = miner;

        room.currMiners++;
        room.currPowerOutput += energy;

        emit Events.MinerBought(player, minerIndex, cost, universalMinerId, row, col);

        _gainHashrate(player, hashrate);
    }

    /// @dev Settle accrued power-bill debt up to `now` using the current energy
    /// total. Per the spec, settlement happens at every miner change (using the
    /// pre-change energy) and at every bill payment; this is the central helper.
    function _settleBill(address player) internal {
        Room storage room = ownerToRoom[player];
        if (room.roomIndex < 2) return; // Trap House has no bill.

        PowerBillState storage bill = ownerToBill[player];
        if (bill.billLastSettlementTimestamp == 0) return;

        uint64 nowTs = uint64(block.timestamp);
        if (nowTs <= bill.billLastSettlementTimestamp) return;

        uint256 elapsed = nowTs - bill.billLastSettlementTimestamp;
        uint256 energy = room.currPowerOutput;
        if (energy > 0) {
            uint256 incremental = (energy * elapsed * BILL_NUMERATOR) / BILL_DENOMINATOR;
            bill.billDebtAccrued += uint128(incremental);
        }
        bill.billLastSettlementTimestamp = nowTs;

        emit Events.PowerBillAccrued(player, bill.billDebtAccrued);
    }

    /// @dev If the 24h window has expired without payment, transition the room
    /// to powerOffline and remove its hashrate from totalEligibleHash. Rewards
    /// up to `now` are settled before the transition so the leak from window-
    /// end to interaction time is bounded by interaction frequency. Anyone can
    /// nudge this transition via `markOffline`.
    function _checkOutage(address player) internal {
        Room storage room = ownerToRoom[player];
        if (room.roomIndex < 2) return;

        PowerBillState storage bill = ownerToBill[player];
        if (bill.powerOffline) return;
        if (bill.billLastSettlementTimestamp == 0) return;
        if (block.timestamp < bill.billWindowEnd) return;

        _updateRewards(player);

        uint256 eligible = playerEligibleHashrate[player];
        if (eligible > 0) {
            totalEligibleHash -= eligible;
            playerEligibleHashrate[player] = 0;
        }
        bill.powerOffline = true;

        emit Events.PowerOutage(player);
    }

    /// @dev Walk the reward accumulator from `lastRewardTimestamp` to `now`,
    /// splitting at month boundaries so each segment uses its correct rate.
    /// Caps at the season end timestamp.
    function _updateCumulativeRewards() internal {
        if (!seasonStarted) return;
        if (totalEligibleHash == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 fromTs = lastRewardTimestamp < seasonStart ? seasonStart : lastRewardTimestamp;
        uint256 endTs = block.timestamp;
        uint256 seasonEnd = seasonStart + SEASON_LENGTH;
        if (endTs > seasonEnd) endTs = seasonEnd;

        while (fromTs < endTs) {
            uint256 rate = _emissionRateAt(fromTs);
            uint256 nextTransition = _nextRateTransition(fromTs);
            uint256 segEnd = nextTransition < endTs ? nextTransition : endTs;
            if (segEnd <= fromTs) break;
            if (rate > 0) {
                cumulativeMethPerHash += (rate * (segEnd - fromTs) * REWARDS_PRECISION) / totalEligibleHash;
            }
            fromTs = segEnd;
        }

        lastRewardTimestamp = block.timestamp;
    }

    function _updateRewards(address player) internal {
        _updateCumulativeRewards();
        uint256 hash = playerEligibleHashrate[player];
        if (hash > 0) {
            playerPendingMethRewards[player] +=
                (hash * (cumulativeMethPerHash - playerMethDebt[player])) / REWARDS_PRECISION;
        }
        playerMethDebt[player] = cumulativeMethPerHash;
    }

    function _emissionRateAt(uint256 ts) internal view returns (uint256) {
        if (ts < seasonStart) return 0;
        uint256 elapsed = ts - seasonStart;
        if (elapsed < MONTH_LENGTH)     return METH_PER_SEC_M1;
        if (elapsed < 2 * MONTH_LENGTH) return METH_PER_SEC_M2;
        if (elapsed < 3 * MONTH_LENGTH) return METH_PER_SEC_M3;
        return 0;
    }

    function _nextRateTransition(uint256 ts) internal view returns (uint256) {
        uint256 m1End = seasonStart + MONTH_LENGTH;
        uint256 m2End = seasonStart + 2 * MONTH_LENGTH;
        uint256 m3End = seasonStart + SEASON_LENGTH;
        if (ts < m1End) return m1End;
        if (ts < m2End) return m2End;
        return m3End;
    }

    function _gainHashrate(address player, uint256 hashrate) internal {
        if (hashrate == 0) return;
        PowerBillState storage bill = ownerToBill[player];
        // Always remember the stored amount so we can re-add on power restoration.
        playerStoredHashrate[player] += hashrate;

        if (bill.powerOffline) {
            // No accumulator change; eligible hash unchanged.
            return;
        }

        _updateRewards(player);
        playerEligibleHashrate[player] += hashrate;
        totalEligibleHash += hashrate;

        emit Events.PlayerHashrateIncreased(player, playerEligibleHashrate[player], playerPendingMethRewards[player]);
    }

    function _loseHashrate(address player, uint256 hashrate) internal {
        if (hashrate == 0) return;
        PowerBillState storage bill = ownerToBill[player];
        // Always reduce stored amount.
        playerStoredHashrate[player] -= hashrate;

        if (bill.powerOffline) {
            // Eligible hash is already zero; nothing to settle.
            return;
        }

        _updateRewards(player);
        playerEligibleHashrate[player] -= hashrate;
        totalEligibleHash -= hashrate;

        emit Events.PlayerHashrateDecreased(player, playerEligibleHashrate[player], playerPendingMethRewards[player]);
    }

    function _isInvalidCoordinates(
        address player,
        uint8 row,
        uint8 col,
        uint8 gridRows,
        uint8 gridCols
    ) internal view returns (bool) {
        if (row >= gridRows || col >= gridCols) return true;
        return playerOccupiedCoords[player][row][col];
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         VIEW FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Compute the player's pending METH-denominated rewards as of now,
    /// without mutating state.
    function pendingRewards(address player) external view returns (uint256) {
        if (!seasonStarted || totalEligibleHash == 0) {
            return playerPendingMethRewards[player];
        }

        uint256 fromTs = lastRewardTimestamp < seasonStart ? seasonStart : lastRewardTimestamp;
        uint256 endTs = block.timestamp;
        uint256 seasonEnd = seasonStart + SEASON_LENGTH;
        if (endTs > seasonEnd) endTs = seasonEnd;

        uint256 simCumulative = cumulativeMethPerHash;
        while (fromTs < endTs) {
            uint256 rate = _emissionRateAt(fromTs);
            uint256 nextTransition = _nextRateTransition(fromTs);
            uint256 segEnd = nextTransition < endTs ? nextTransition : endTs;
            if (segEnd <= fromTs) break;
            if (rate > 0) {
                simCumulative += (rate * (segEnd - fromTs) * REWARDS_PRECISION) / totalEligibleHash;
            }
            fromTs = segEnd;
        }

        uint256 hash = playerEligibleHashrate[player];
        return playerPendingMethRewards[player]
            + (hash * (simCumulative - playerMethDebt[player])) / REWARDS_PRECISION;
    }

    /// @notice Live debt for the player's current bill window (accrued + new accrual since last settle).
    function currentBillDebt(address player) external view returns (uint256) {
        Room memory room = ownerToRoom[player];
        if (room.roomIndex < 2) return 0;

        PowerBillState memory bill = ownerToBill[player];
        if (bill.billLastSettlementTimestamp == 0) return 0;

        uint256 elapsed = block.timestamp > bill.billLastSettlementTimestamp
            ? block.timestamp - bill.billLastSettlementTimestamp
            : 0;
        uint256 incremental = 0;
        if (elapsed > 0 && room.currPowerOutput > 0) {
            incremental = (uint256(room.currPowerOutput) * elapsed * BILL_NUMERATOR) / BILL_DENOMINATOR;
        }
        return uint256(bill.billDebtAccrued) + incremental;
    }

    /// @notice METH emissions per second at the current block timestamp.
    function currentEmissionRate() external view returns (uint256) {
        if (!seasonStarted) return 0;
        return _emissionRateAt(block.timestamp);
    }

    /// @notice Seconds until the player can upgrade to the next room.
    function timeUntilNextRoomUpgrade(address player) external view returns (uint256) {
        uint256 last = lastRoomUpgradeTimestamp[player];
        if (last == 0) return 0;
        Room memory r = ownerToRoom[player];
        if (r.roomIndex == 0 || r.roomIndex == roomConfigCount) return 0;
        uint64 cooldown = roomConfigs[r.roomIndex + 1].cooldown;
        uint256 ready = last + cooldown;
        return block.timestamp >= ready ? 0 : ready - block.timestamp;
    }

    function getPlayerMinersPaginated(address player, uint256 startIndex, uint256 size)
        external
        view
        returns (Miner[] memory)
    {
        EnumerableSetLib.Uint256Set storage set = playerMinersOwned[player];
        uint256 length = set.length();
        if (startIndex >= length) return new Miner[](0);

        uint256 remaining = length - startIndex;
        uint256 returnSize = size > remaining ? remaining : size;
        Miner[] memory miners = new Miner[](returnSize);
        for (uint256 i = 0; i < returnSize; i++) {
            miners[i] = playerMinersId[set.at(startIndex + i)];
        }
        return miners;
    }

    function isPlayerOnClaimCooldown(address player) internal view returns (bool) {
        return (block.timestamp < playerLastClaim[player] + playerClaimCooldown);
    }

    function getRoomConfig(uint256 idx) external view returns (RoomConfig memory) {
        return roomConfigs[idx];
    }

    function getMinerTemplate(uint256 idx) external view returns (MinerTemplate memory) {
        return minerTemplates[idx];
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        OWNER FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Add a new miner template. Index is assigned sequentially.
    function addMinerTemplate(uint32 hashrate, uint32 energy, uint256 cost, bool inProduction) external onlyOwner {
        _addMinerTemplate(hashrate, energy, cost, inProduction);
    }

    /// @notice Add multiple miner templates atomically. Indices are assigned
    /// sequentially in array order. Reverts the entire batch on any failure.
    function batchAddMinerTemplates(MinerTemplate[] calldata templates) external onlyOwner {
        for (uint256 i = 0; i < templates.length; i++) {
            MinerTemplate calldata t = templates[i];
            _addMinerTemplate(t.hashrate, t.energy, t.cost, t.inProduction);
        }
    }

    function _addMinerTemplate(uint32 hashrate, uint32 energy, uint256 cost, bool inProduction) internal {
        ++uniqueMinerCount;
        minerTemplates[uniqueMinerCount] = MinerTemplate(hashrate, energy, cost, inProduction);
        emit Events.NewMinerTemplateAdded(uniqueMinerCount, hashrate, energy, cost, inProduction);
    }

    function toggleMinerProduction(uint256 minerIndex, bool inProduction) external onlyOwner {
        if (minerIndex == 0 || minerIndex > uniqueMinerCount) revert Errors.InvalidMinerIndex();
        minerTemplates[minerIndex].inProduction = inProduction;
        emit Events.MinerProductionToggled(minerIndex, inProduction);
    }

    function changeMinerCost(uint256 minerIndex, uint256 newCost) external onlyOwner {
        if (minerIndex > uniqueMinerCount || minerIndex == 0) revert Errors.NonExistentMiner();
        if (minerIndex == STARTER_MINER_INDEX) revert Errors.CantModifyStarterMiner();
        minerTemplates[minerIndex].cost = newCost;
        emit Events.MinerCostChanged(minerIndex, newCost);
    }

    /// @notice Add a new room config. Index is assigned sequentially.
    /// `gridRows * gridCols` must equal `maxMiners`. Power and grid must be
    /// non-decreasing relative to the previous room.
    function addRoomConfig(
        uint8 maxMiners,
        uint32 totalPowerOutput,
        uint256 cost,
        bool inProduction,
        uint8 gridRows,
        uint8 gridCols,
        uint64 cooldown
    ) external onlyOwner {
        _addRoomConfig(maxMiners, totalPowerOutput, cost, inProduction, gridRows, gridCols, cooldown);
    }

    /// @notice Add multiple room configs atomically. Indices are assigned
    /// sequentially in array order, and each entry is validated against the
    /// previously-added one. Reverts the entire batch on any failure.
    function batchAddRoomConfigs(RoomConfig[] calldata configs) external onlyOwner {
        for (uint256 i = 0; i < configs.length; i++) {
            RoomConfig calldata c = configs[i];
            _addRoomConfig(c.maxMiners, c.totalPowerOutput, c.cost, c.inProduction, c.gridRows, c.gridCols, c.cooldown);
        }
    }

    function _addRoomConfig(
        uint8 maxMiners,
        uint32 totalPowerOutput,
        uint256 cost,
        bool inProduction,
        uint8 gridRows,
        uint8 gridCols,
        uint64 cooldown
    ) internal {
        if (uint256(gridRows) * uint256(gridCols) != maxMiners) revert Errors.FacilityDimensionsInvalid();

        RoomConfig memory prev = roomConfigs[roomConfigCount];
        if (prev.gridRows > gridRows || prev.gridCols > gridCols) revert Errors.FacilityDimensionsInvalid();
        if (prev.totalPowerOutput > totalPowerOutput) revert Errors.InvalidPowerOutput();

        ++roomConfigCount;
        roomConfigs[roomConfigCount] = RoomConfig({
            maxMiners: maxMiners,
            totalPowerOutput: totalPowerOutput,
            cost: cost,
            inProduction: inProduction,
            gridRows: gridRows,
            gridCols: gridCols,
            cooldown: cooldown
        });

        emit Events.NewRoomConfigAdded(roomConfigCount, maxMiners, totalPowerOutput, cost, inProduction, gridRows, gridCols, cooldown);
    }

    function toggleRoomProduction(uint256 roomIndex, bool inProduction) external onlyOwner {
        if (roomIndex == 0 || roomIndex > roomConfigCount) revert Errors.InvalidFacilityIndex();
        roomConfigs[roomIndex].inProduction = inProduction;
        emit Events.RoomProductionToggled(roomIndex, inProduction);
    }

    function changeRoomCost(uint256 roomIndex, uint256 newCost) external onlyOwner {
        if (roomIndex == 0 || roomIndex > roomConfigCount) revert Errors.NonExistentFacility();
        if (roomIndex == STARTER_ROOM_INDEX) revert Errors.CantModifyStarterFacility();
        roomConfigs[roomIndex].cost = newCost;
        emit Events.RoomCostChanged(roomIndex, newCost);
    }

    /// @notice Start the 90-day season clock. Call this at METH TGE.
    function startSeason(uint256 _seasonStart) external onlyOwner {
        if (seasonStarted) revert Errors.SeasonAlreadyStarted();
        seasonStarted = true;
        seasonStart = _seasonStart == 0 ? block.timestamp : _seasonStart;
        lastRewardTimestamp = seasonStart;
        emit Events.SeasonStarted(seasonStart);
    }

    function setMeth(address _meth) external onlyOwner {
        if (_meth == address(0)) revert Errors.ZeroAddress();
        meth = _meth;
    }

    function setDMeth(address _dmeth) external onlyOwner {
        if (_dmeth == address(0)) revert Errors.ZeroAddress();
        dmeth = _dmeth;
    }

    function setMinerNFT(address _minerNFT) external onlyOwner {
        if (_minerNFT == address(0)) revert Errors.ZeroAddress();
        minerNFT = _minerNFT;
    }

    function setCheckNFT(address _checkNFT) external onlyOwner {
        if (_checkNFT == address(0)) revert Errors.ZeroAddress();
        checkNFT = _checkNFT;
    }

    function setBagNFT(address _bagNFT) external onlyOwner {
        if (_bagNFT == address(0)) revert Errors.ZeroAddress();
        bagNFT = _bagNFT;
    }

    function setTokenDistribution(address _tokenDistribution) external onlyOwner {
        if (_tokenDistribution == address(0)) revert Errors.ZeroAddress();
        tokenDistribution = _tokenDistribution;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert Errors.ZeroAddress();
        treasury = _treasury;
    }

    function setInitialRoomPrice(uint256 _initialPrice) external onlyOwner {
        initialRoomPrice = _initialPrice;
    }

    /// @notice Authorize an external contract (e.g. Packs) to reserve unique
    /// minerIds against `universalMinerId`. This prevents id collisions between
    /// in-game purchases and externally minted MinerNFTs.
    function setMinerIdReserver(address reserver, bool authorized) external onlyOwner {
        if (reserver == address(0)) revert Errors.ZeroAddress();
        authorizedMinerIdReservers[reserver] = authorized;
    }

    /// @notice Reserve the next universal minerId. Only callable by authorized
    /// reservers. Each call increments the universal counter and returns the
    /// fresh id.
    function reserveMinerId() external returns (uint32) {
        if (!authorizedMinerIdReservers[msg.sender]) revert Errors.NotAuthorized();
        ++universalMinerId;
        return universalMinerId;
    }

    /// @notice Withdraw collected ETH (from room 1 purchases) to the treasury.
    function withdraw() external onlyOwner nonReentrant {
        if (treasury == address(0)) revert Errors.ZeroAddress();
        uint256 balance = address(this).balance;
        (bool success,) = payable(treasury).call{value: balance}("");
        if (!success) revert Errors.WithdrawFailed();
    }
}
