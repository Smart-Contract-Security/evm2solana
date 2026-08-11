// SPDX-License-Identifier: MIT

import '../libs/Stakes.sol';

interface IStaking {
    function setMinimumStake(uint64 _minimumStake) external;

    function setLockPeriod(uint32 _lockPeriod) external;

    function getAvailableStake(address _staker) external view returns (uint64);

    function getStakedTokens(address _staker) external view returns (uint64);

    function stake(uint64 _tokens) external;

    function unstake(uint64 _tokens) external;

    function withdraw() external;

    function slash(
        address _slasher,
        address _staker,
        address _escrowAddress,
        uint64 _tokens
    ) external;

    function getListOfStakers(
        uint64 _startIndex,
        uint64 _limit
    ) external view returns (address[] memory, Stakes.Staker[] memory);

    function withdrawFees() external;

    function addSlasher(address _slasher) external;

    function removeSlasher(address _slasher) external;
}