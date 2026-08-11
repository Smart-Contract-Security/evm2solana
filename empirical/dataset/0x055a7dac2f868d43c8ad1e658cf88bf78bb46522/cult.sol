// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*

CULT — The Holder-Only Confession Wall

CULT is an ERC-20 that turns holders into believers.

Hold to enter.
Confess to speak.
Pray to build faith.
Sacrifice to be remembered.
Rise through ranks.
Leave your words on-chain forever.

Most tokens track balances.
CULT tracks belief.

The chart is the entrance.
The contract is the temple.
The cult remembers.

*/

contract CULT is ERC20 {
    uint256 public constant MAX_MESSAGE_LENGTH = 280;
    uint256 public constant CONFESSION_COOLDOWN = 1 hours;

    uint256 public immutable templeOpenedAt;

    uint256 public totalBelievers;
    uint256 public totalConfessions;
    uint256 public totalPrayers;
    uint256 public totalSacrificed;
    uint256 public totalTransfersRemembered;

    address public firstBeliever;
    address public lastBeliever;
    address public lastConfessor;
    address public lastSacrificer;

    string public lastConfession;
    string public lastCarving;

    struct Believer {
        uint256 firstSeenAt;
        uint256 firstSeenBlock;
        uint256 confessions;
        uint256 prayers;
        uint256 currentStreak;
        uint256 bestStreak;
        uint256 lastPrayerDay;
        uint256 lastConfessionAt;
        uint256 sacrificed;
        uint256 carvings;
    }

    struct Carving {
        address believer;
        uint256 amount;
        uint256 timestamp;
        string message;
    }

    mapping(address => Believer) private _believers;
    Carving[] private _carvings;

    event EnteredTemple(address indexed believer, uint256 timestamp, uint256 blockNumber);

    event Confession(
        address indexed believer,
        uint256 indexed confessionId,
        string message,
        uint256 timestamp
    );

    event Prayer(
        address indexed believer,
        uint256 totalPrayersByBeliever,
        uint256 currentStreak,
        uint256 bestStreak,
        uint256 timestamp
    );

    event Sacrifice(
        address indexed believer,
        uint256 amount,
        uint256 indexed carvingId,
        string message,
        uint256 timestamp
    );

    event RememberedTransfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 indexed transferNumber
    );

    constructor(
        uint256 initialSupply,
        address initialReceiver
    ) ERC20("CULT", "CULT") {
        require(initialReceiver != address(0), "zero receiver");

        templeOpenedAt = block.timestamp;

        _mint(initialReceiver, initialSupply);
        _remember(initialReceiver);
    }

    function confess(string calldata message) external {
        _requireHolder(msg.sender);
        _requireValidMessage(message);

        Believer storage b = _believers[msg.sender];

        require(
            block.timestamp >= b.lastConfessionAt + CONFESSION_COOLDOWN,
            "confession cooldown"
        );

        _remember(msg.sender);

        b.confessions += 1;
        b.lastConfessionAt = block.timestamp;

        totalConfessions += 1;
        lastConfessor = msg.sender;
        lastBeliever = msg.sender;
        lastConfession = message;

        emit Confession(msg.sender, totalConfessions, message, block.timestamp);
    }

    function pray() external {
        _requireHolder(msg.sender);
        _remember(msg.sender);

        Believer storage b = _believers[msg.sender];

        uint256 todayNumber = block.timestamp / 1 days;

        require(b.lastPrayerDay < todayNumber, "already prayed today");

        if (b.lastPrayerDay + 1 == todayNumber) {
            b.currentStreak += 1;
        } else {
            b.currentStreak = 1;
        }

        b.lastPrayerDay = todayNumber;
        b.prayers += 1;

        if (b.currentStreak > b.bestStreak) {
            b.bestStreak = b.currentStreak;
        }

        totalPrayers += 1;
        lastBeliever = msg.sender;

        emit Prayer(
            msg.sender,
            b.prayers,
            b.currentStreak,
            b.bestStreak,
            block.timestamp
        );
    }

    function sacrifice(uint256 amount, string calldata message) external {
        _requireHolder(msg.sender);
        _requireValidMessage(message);

        require(amount > 0, "zero sacrifice");
        require(balanceOf(msg.sender) >= amount, "insufficient balance");

        _remember(msg.sender);

        _burn(msg.sender, amount);

        Believer storage b = _believers[msg.sender];

        b.sacrificed += amount;
        b.carvings += 1;

        totalSacrificed += amount;
        lastSacrificer = msg.sender;
        lastBeliever = msg.sender;
        lastCarving = message;

        _carvings.push(
            Carving({
                believer: msg.sender,
                amount: amount,
                timestamp: block.timestamp,
                message: message
            })
        );

        emit Sacrifice(
            msg.sender,
            amount,
            _carvings.length - 1,
            message,
            block.timestamp
        );
    }

    function believerOf(address user) external view returns (Believer memory) {
        return _believers[user];
    }

    function carvingCount() external view returns (uint256) {
        return _carvings.length;
    }

    function carvingAt(uint256 id) external view returns (Carving memory) {
        require(id < _carvings.length, "bad carving id");
        return _carvings[id];
    }

    function canConfess(address user) external view returns (bool) {
        if (balanceOf(user) == 0) return false;

        Believer memory b = _believers[user];

        return block.timestamp >= b.lastConfessionAt + CONFESSION_COOLDOWN;
    }

    function faithOf(address user) public view returns (uint256) {
        Believer memory b = _believers[user];

        uint256 balanceFaith = balanceOf(user) / 1e18;
        uint256 prayerFaith = b.prayers * 10;
        uint256 confessionFaith = b.confessions * 25;
        uint256 streakFaith = b.bestStreak * 50;
        uint256 sacrificeFaith = b.sacrificed / 1e18;

        return balanceFaith + prayerFaith + confessionFaith + streakFaith + sacrificeFaith;
    }

    function rankOf(address user) public view returns (string memory) {
        if (balanceOf(user) == 0) {
            return "Outsider";
        }

        uint256 faith = faithOf(user);
        Believer memory b = _believers[user];

        if (b.sacrificed > 0 && faith >= 1_000_000) {
            return "Martyr";
        }

        if (faith >= 10_000_000) {
            return "Prophet";
        }

        if (faith >= 1_000_000) {
            return "High Priest";
        }

        if (faith >= 100_000) {
            return "Disciple";
        }

        if (faith >= 10_000) {
            return "Believer";
        }

        return "Watcher";
    }

    function mood() external view returns (string memory) {
        if (block.timestamp > templeOpenedAt + 7 days && totalConfessions == 0) {
            return "Silent";
        }

        if (totalSacrificed >= totalSupply() / 10) {
            return "Ascended";
        }

        if (totalSacrificed >= totalSupply() / 100) {
            return "Hungry";
        }

        if (totalConfessions >= 1_000 || totalPrayers >= 5_000) {
            return "Possessed";
        }

        if (totalConfessions >= 100 || totalPrayers >= 500) {
            return "Awakening";
        }

        return "Dormant";
    }

    function temple() external pure returns (string memory) {
        return
            "Buy to enter. Hold to speak. Pray to build faith. Burn to be remembered. The cult remembers.";
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (from != address(0) && to != address(0) && value > 0) {
            totalTransfersRemembered += 1;

            _remember(to);

            emit RememberedTransfer(
                from,
                to,
                value,
                totalTransfersRemembered
            );
        }
    }

    function _remember(address user) internal {
        if (user == address(0)) return;

        Believer storage b = _believers[user];

        if (b.firstSeenAt == 0) {
            b.firstSeenAt = block.timestamp;
            b.firstSeenBlock = block.number;

            totalBelievers += 1;

            if (firstBeliever == address(0)) {
                firstBeliever = user;
            }

            emit EnteredTemple(user, block.timestamp, block.number);
        }

        lastBeliever = user;
    }

    function _requireHolder(address user) internal view {
        require(balanceOf(user) > 0, "outsider");
    }

    function _requireValidMessage(string calldata message) internal pure {
        uint256 len = bytes(message).length;

        require(len > 0, "empty message");
        require(len <= MAX_MESSAGE_LENGTH, "message too long");
    }
}