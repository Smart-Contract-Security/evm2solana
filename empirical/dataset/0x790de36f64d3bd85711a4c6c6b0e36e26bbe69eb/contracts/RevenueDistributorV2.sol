// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/openzeppelin/access/Ownable.sol";
import "./lib/openzeppelin/security/ReentrancyGuard.sol";
import "./lib/openzeppelin/utils/Address.sol";

interface IHousePoolYield {
    function notifyYield() external payable;
}

interface IJMYStakingYield {
    function notifyRewardAmount() external payable;
}

/// @title RevenueDistributorV2
/// @notice Push router that splits incoming APE between treasury, HousePool LPs,
///         and JMYStaking. Split BPS are admin-settable (must sum to BASIS_POINTS).
contract RevenueDistributorV2 is Ownable, ReentrancyGuard {
    using Address for address payable;

    uint256 public constant BASIS_POINTS = 10000;

    uint256 public treasuryBps;
    uint256 public lpBps;
    uint256 public stakerBps;

    address payable public treasury;
    IHousePoolYield public housePool;
    IJMYStakingYield public jmyStaking;

    event RevenueRouted(uint256 totalIn, uint256 toTreasury, uint256 toPool, uint256 toStakers);
    event EndpointsUpdated(address treasury, address housePool, address jmyStaking);
    event SplitUpdated(uint256 treasuryBps, uint256 lpBps, uint256 stakerBps);

    constructor(address initialOwner) {
        treasuryBps = 1000;  // 10%
        lpBps       = 8000;  // 80%
        stakerBps   = 1000;  // 10%

        if (initialOwner != address(0) && initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
    }

    function setEndpoints(
        address payable _treasury,
        address _housePool,
        address _jmyStaking
    ) external onlyOwner {
        require(_treasury != address(0), "RD: zero treasury");
        require(_housePool != address(0), "RD: zero pool");
        require(_jmyStaking != address(0), "RD: zero staking");
        treasury = _treasury;
        housePool = IHousePoolYield(_housePool);
        jmyStaking = IJMYStakingYield(_jmyStaking);
        emit EndpointsUpdated(_treasury, _housePool, _jmyStaking);
    }

    /// @notice Atomically set the three split percentages. Must sum to BASIS_POINTS.
    function setSplit(uint256 _treasuryBps, uint256 _lpBps, uint256 _stakerBps) external onlyOwner {
        require(_treasuryBps + _lpBps + _stakerBps == BASIS_POINTS, "RD: split != 100%");
        treasuryBps = _treasuryBps;
        lpBps       = _lpBps;
        stakerBps   = _stakerBps;
        emit SplitUpdated(_treasuryBps, _lpBps, _stakerBps);
    }

    function distribute() external payable nonReentrant {
        uint256 amount = msg.value;
        require(amount > 0, "RD: zero value");
        require(
            treasury != address(0) &&
            address(housePool) != address(0) &&
            address(jmyStaking) != address(0),
            "RD: endpoints unset"
        );

        uint256 toTreasury = (amount * treasuryBps) / BASIS_POINTS;
        uint256 toStakers  = (amount * stakerBps) / BASIS_POINTS;
        uint256 toPool     = amount - toTreasury - toStakers;

        if (toTreasury > 0) treasury.sendValue(toTreasury);
        if (toStakers > 0) jmyStaking.notifyRewardAmount{value: toStakers}();
        if (toPool > 0) housePool.notifyYield{value: toPool}();

        emit RevenueRouted(amount, toTreasury, toPool, toStakers);
    }

    receive() external payable {
        revert("RD: use distribute()");
    }
}
