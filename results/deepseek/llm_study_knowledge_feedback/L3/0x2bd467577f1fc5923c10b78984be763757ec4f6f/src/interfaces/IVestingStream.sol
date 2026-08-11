// SPDX-License-Identifier: MIT

import 'solana';

interface IVestingStream {
    // Error definitions not supported on Solana, using revert with string messages instead

    event Claimed(uint256 indexed allocationId, address indexed recipient, uint256 amount);
    event VestingInitialized(uint256 cliffEnd, uint256 vestingEnd, uint256 allocationCount);
    event RecipientAddressChanged(uint256 indexed allocationId, address oldAddress, address newAddress);

    function setInitializer(
        address _initializer,
        address _issuer
    ) external;
    function initialize(
        address token,
        uint64 liquiditySeedTime,
        address[] calldata recipients,
        uint64[] calldata amounts
    ) external;
    function claim(
        uint64 allocationId
    ) external;
    function executeChangeRecipientAddress(
        uint64 allocationId,
        address newAddress
    ) external;
    function claimable(
        uint64 allocationId
    ) external view returns (uint64);
    function totalVested(
        uint64 allocationId
    ) external view returns (uint64);
    function allocationCount() external view returns (uint64);
    function cliffEnd() external view returns (uint64);
    function vestingEnd() external view returns (uint64);
    function issuer() external view returns (address);
}