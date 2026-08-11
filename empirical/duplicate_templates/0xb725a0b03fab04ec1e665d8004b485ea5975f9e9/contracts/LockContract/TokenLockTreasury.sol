// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @dev This contract is designed for lock token and release token after end lock.
 * Has function to start lock token for when user ready start lock.
 * Has function to release token after end lock user can release token.
 */

contract TokenLockTreasury is Ownable, AccessControl {
    using SafeERC20 for IERC20;
    struct RoundRelease {
        uint256 releaseIntervals;
        uint256 releasePortions;
    }

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @dev Days times 86400 second = 1 day. 
    uint256 public constant Days = 86400; 

    /// @dev Address of token address want to use lock.  
    IERC20 public immutable token;

    /// @dev Number of days locked.
    uint256 public immutable lockDuration;

    uint256 public startLockTimes;
    uint256 public endLockTimes;
    uint256 public totalLockToken;
    RoundRelease[] public roundRelease;
    uint256 public totalReleaseToken;
    uint256 public currentLockToken;

    /// @dev Status release token.
    bool public releaseTokenFinish;

    event RoundReleaseAdded(uint256 indexed index, uint256 releaseInterval, uint256 releasePortion);
    event StartLockToken(uint256 lockAmount, uint256 startLockTimes, uint256 endLockTimes);
    event ReleaseToken(address indexed receiver, uint256 releaseAmount, uint256 releaseTimes);

    constructor(
        address _tokenAddress,
        uint256 _lockDuration,
        RoundRelease[] memory _roundRelease,
        address _owner
    ) Ownable(_owner) {
        token = IERC20(_tokenAddress);
        lockDuration = _lockDuration;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(OWNER_ROLE, _owner);
        for (uint256 i = 0; i < _roundRelease.length; i++) {
            roundRelease.push(_roundRelease[i]);
            emit RoundReleaseAdded(
                i,
                _roundRelease[i].releaseIntervals,
                _roundRelease[i].releasePortions
            );
        }
    }

    receive() external payable {
        revert("[TokenLockTreasury] Revert receive function");
    }

    fallback() external payable {
        revert("[TokenLockTreasury] Revert fallback function");
    }

     /**
     * @dev Start lock token for when user ready start lock.
     * This function is called by authorized users "OWNER_ROLE".
     * User need to approve this contract in token contract in order to start lock token.
     * @param _lockTokenAmount - Amount of token.
     */
    function startLockToken(uint256 _lockTokenAmount) external onlyRole(OWNER_ROLE){
        require(startLockTimes == 0, "[TokenLockTreasury.startLockToken] Token lock get start locked");
        require(
            _lockTokenAmount > 0,
            "[TokenLockTreasury.startLockToken] Token lock amount have to not be zero"
        );
        startLockTimes = block.timestamp;
        endLockTimes = block.timestamp + (lockDuration * Days);
        totalLockToken = _lockTokenAmount;
        currentLockToken = _lockTokenAmount;
        token.safeTransferFrom(msg.sender, address(this), _lockTokenAmount);

        emit StartLockToken(_lockTokenAmount, startLockTimes, endLockTimes);
    }

     /**
     * @dev Release Token after end lock user can release token.
     * Release token follow round release.
     * @param _receiver - Adress of receiver.
     */

    function releaseToken(address _receiver) external onlyRole(OWNER_ROLE){
        require(!releaseTokenFinish, "[TokenLockTreasury.releaseToken] Release token is finish");
        require(
            block.timestamp >= endLockTimes,
            "[TokenLockTreasury.releaseToken] Lock token isn't over yet"
        );
        uint256 releaseAmount = calculateReleaseAmount();
        require(releaseAmount > 0, "[TokenLockTreasury.releaseToken] Zero release amount");
        totalReleaseToken += releaseAmount;
        currentLockToken -= releaseAmount;
        token.safeTransfer(_receiver, releaseAmount);
        if (currentLockToken == 0) {
            releaseTokenFinish = true;
        }
        emit ReleaseToken(_receiver, releaseAmount, block.timestamp);
    }
     /**
     * @dev calculate release amount use in release token function.
     * Will calculate after end lock.
     */
    function calculateReleaseAmount() public view returns (uint256) {
        uint256 releaseTokenAmount;
        uint256 totalReleasePortion;
        uint256 currentTime = block.timestamp;
        if (currentTime >= endLockTimes + (roundRelease[0].releaseIntervals * Days)) {
            for (uint256 i = 0; i < roundRelease.length; i++) {
                if (currentTime >= endLockTimes + (roundRelease[i].releaseIntervals * Days)) {
                    totalReleasePortion += roundRelease[i].releasePortions;
                } else {
                    break;
                }
            }
            releaseTokenAmount =
                ((totalReleasePortion * totalLockToken) / 10000) -
                totalReleaseToken;
        }
        return releaseTokenAmount;
    }

    /**
     * @dev Get round release.
     * For check detail round release.
     */
    function getRoundRelease() external view returns (RoundRelease[] memory) {
        return roundRelease;
    }

    /**
     * @dev Get day passed.
     * For check day passed after start lock token.
     */
    function getDayPassed() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 elapsedTime = currentTime - startLockTimes;
        uint256 dayPassed = elapsedTime / Days;
        return dayPassed;
    }

    /**
     * @dev Get day release days passed.
     * For check release day passed after end lock token.
     */
    function getReleaseDaysPassed() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 elapsedTime = currentTime - endLockTimes;
        uint256 dayPassed = elapsedTime / Days;
        return dayPassed;
    }

     /**
     * @dev Get lock days balance.
     * For check lock days balance after start lock token.
     */
    function getLockDaysBalance() public view returns (uint256) {
        uint256 currenttimes = (block.timestamp - (block.timestamp % Days)) / Days;
        uint256 endDay = (endLockTimes - (endLockTimes % Days)) / Days;
        uint256 daysBalance;
        if (currenttimes >= endDay) {
            daysBalance = 0;
        } else {
            daysBalance = endDay - currenttimes;
        }
        return daysBalance;
    }
}