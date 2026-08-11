// SPDX-License-Identifier: MIT

import 'solana';

interface IBoardwalkToken {
    event TokenInitialized(
        string name,
        string symbol,
        uint64 baseTaxBps,
        uint64 antiWhaleTaxBps,
        uint64 antiWhaleDuration,
        address feeDistributor,
        address presaleManager
    );
    event LiquiditySeedTimeSet(uint64 seedTime);

    function initialize(
        string calldata name,
        string calldata ticker,
        uint64 baseTaxBps,
        uint64 antiWhaleTaxBps,
        uint64 antiWhaleDuration,
        address feeDistributor,
        address presaleManager,
        address[] calldata exemptAddresses
    ) external;
    function mint(
        address to,
        uint64 amount
    ) external;
    function setLiquiditySeedTime(
        uint64 seedTime
    ) external;
    function updateExempt(
        address account,
        bool exempt
    ) external;
    function isExempt(
        address account
    ) external view returns (bool);
    function baseTaxBps() external view returns (uint64);
    function antiWhaleTaxBps() external view returns (uint64);
    function antiWhaleDuration() external view returns (uint64);
    function liquiditySeedTime() external view returns (uint64);
    function feeDistributor() external view returns (address);
    function presaleManager() external view returns (address);
}