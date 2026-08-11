// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IMethBurnable {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burn(uint256 value) external;
}

interface IDMethMintable {
    function mint(address to, uint256 amount) external;
}

/**
 * @title MethConverter
 * @notice One-way 1:1 conversion of METH into dMETH. METH is burned on conversion;
 * fresh dMETH is minted to the user. Per-wallet rolling-24h caps tighten/loosen by
 * phase (first 48h post-TGE, then per-month).
 *
 * The reverse direction (dMETH → METH) does not exist by design.
 */
contract MethConverter is Ownable {
    address public meth;
    address public dmeth;
    uint64 public tgeTimestamp;
    bool public paused;

    // Per-wallet rolling 24h conversion accounting.
    mapping(address => uint256) public dailyConvertedAmount;
    mapping(address => uint64) public dailyWindowStart;

    // Phase caps (METH wei). Defaults match the whitepaper.
    uint256 public cap48h     = 5_000e18;
    uint256 public capMonth1  = 20_000e18;
    uint256 public capMonth2  = 50_000e18;
    uint256 public capMonth3  = 100_000e18;

    uint64 public constant DAY = 1 days;

    event Converted(address indexed user, uint256 methIn, uint256 dmethOut);
    event PausedChanged(bool paused);
    event TGESet(uint64 timestamp);
    event CapsUpdated(uint256 cap48h, uint256 capMonth1, uint256 capMonth2, uint256 capMonth3);
    event MethUpdated(address indexed meth);
    event DMethUpdated(address indexed dmeth);

    error PausedError();
    error TGENotSet();
    error CapExceeded();
    error ZeroAmount();
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    function convert(uint256 methAmount) external {
        if (paused) revert PausedError();
        if (methAmount == 0) revert ZeroAmount();
        if (tgeTimestamp == 0) revert TGENotSet();

        uint256 cap = _currentCap();
        _settleDailyWindow(msg.sender);
        if (dailyConvertedAmount[msg.sender] + methAmount > cap) revert CapExceeded();

        dailyConvertedAmount[msg.sender] += methAmount;

        // Pull METH from user, burn it permanently.
        IMethBurnable(meth).transferFrom(msg.sender, address(this), methAmount);
        IMethBurnable(meth).burn(methAmount);

        // Mint dMETH 1:1.
        IDMethMintable(dmeth).mint(msg.sender, methAmount);

        emit Converted(msg.sender, methAmount, methAmount);
    }

    function _settleDailyWindow(address user) internal {
        uint64 ws = dailyWindowStart[user];
        if (ws == 0 || block.timestamp >= ws + DAY) {
            dailyWindowStart[user] = uint64(block.timestamp);
            dailyConvertedAmount[user] = 0;
        }
    }

    function _currentCap() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - tgeTimestamp;
        if (elapsed < 48 hours) return cap48h;
        if (elapsed < 30 days) return capMonth1;
        if (elapsed < 60 days) return capMonth2;
        return capMonth3;
    }

    function currentDailyCap() external view returns (uint256) {
        if (tgeTimestamp == 0) return 0;
        return _currentCap();
    }

    function remainingDailyCap(address user) external view returns (uint256) {
        if (tgeTimestamp == 0) return 0;
        uint256 cap = _currentCap();
        uint64 ws = dailyWindowStart[user];
        if (ws == 0 || block.timestamp >= ws + DAY) {
            return cap;
        }
        uint256 used = dailyConvertedAmount[user];
        return used >= cap ? 0 : cap - used;
    }

    // ━━━ Admin ━━━

    function setMeth(address _meth) external onlyOwner {
        if (_meth == address(0)) revert ZeroAddress();
        meth = _meth;
        emit MethUpdated(_meth);
    }

    function setDMeth(address _dmeth) external onlyOwner {
        if (_dmeth == address(0)) revert ZeroAddress();
        dmeth = _dmeth;
        emit DMethUpdated(_dmeth);
    }

    function setTGE(uint64 timestamp) external onlyOwner {
        tgeTimestamp = timestamp;
        emit TGESet(timestamp);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedChanged(_paused);
    }

    function setCaps(uint256 _cap48h, uint256 _capMonth1, uint256 _capMonth2, uint256 _capMonth3) external onlyOwner {
        cap48h = _cap48h;
        capMonth1 = _capMonth1;
        capMonth2 = _capMonth2;
        capMonth3 = _capMonth3;
        emit CapsUpdated(_cap48h, _capMonth1, _capMonth2, _capMonth3);
    }
}
