// SPDX-License-Identifier: MIT

import 'solana';

interface IPresaleManager {
    event Contributed(address indexed user, uint64 amount, uint64 bonusMultiplier);
    event TokensClaimed(address indexed user, uint64 amount);
    event PresaleInitialized(address token, uint64 presaleStart, uint64 presaleEnd, uint64 graduationThreshold);
    event VestingConfigSet(uint64 recipientCount);
    event LiquiditySeeded(uint64 raiseAmount, uint64 tokenAmount, uint64 lpTokens);
    event Refunded(address indexed user, uint64 amount);

    function initialize(
        address token,
        address feeDistributor,
        address vestingStream,
        address lpStaking,
        address router,
        address raiseToken,
        address dexFactory,
        uint64 duration,
        uint64 presalePercent,
        uint64 graduationThreshold,
        bool hasDelay
    ) external;
    function setVestingConfig(
        address[] calldata recipients,
        uint64[] calldata amounts
    ) external;
    function contribute(
        uint64 amount
    ) external;
    function seedLiquidity() external;
    function claimTokens() external;
    function refund() external;
    function calculateTokens(
        address account
    ) external view returns (uint64);
    function totalRaised() external view returns (uint64);
    function totalWeightedRaise() external view returns (uint64);
    function seeded() external view returns (bool);
    function presaleStart() external view returns (uint64);
    function presaleEnd() external view returns (uint64);
    function liquiditySeedTime() external view returns (uint64);
}