// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISpaceDues {
    struct Terms {
        address token;
        uint256 amount;
        uint64 periodSeconds;
        uint64 graceSeconds;
        address treasury;
        bool active;
    }

    event PaymentTokenAllowed(address indexed token, bool allowed);
    event TermsUpdated(
        bytes32 indexed spaceKey,
        address indexed token,
        uint256 amount,
        uint64 periodSeconds,
        uint64 graceSeconds,
        address treasury,
        bool active
    );
    event AmountUpdated(bytes32 indexed spaceKey, uint256 amount);
    event DuesPaid(
        bytes32 indexed spaceKey,
        uint32 indexed urbitId,
        address indexed payer,
        address token,
        uint32 periods,
        uint256 amount,
        uint64 paidThrough
    );
    event DuesClaimed(bytes32 indexed spaceKey, address indexed token, address indexed recipient, uint256 amount);

    function setPaymentTokenAllowed(address token, bool allowed) external;
    function setTerms(bytes32 spaceKey, Terms calldata newTerms) external;
    function setAmount(bytes32 spaceKey, uint256 newAmount) external;
    function pay(bytes32 spaceKey, uint32 urbitId, uint32 periods) external returns (uint64 newPaidThrough);
    function isPaid(bytes32 spaceKey, uint32 urbitId) external view returns (bool);
    function accessStatus(bytes32 spaceKey, uint32 urbitId)
        external
        view
        returns (
            bool spaceExists,
            bool destroyed,
            bool duesActive,
            bool isMember,
            bool isBanned,
            bool paid,
            uint64 paidThrough,
            uint64 graceEnds,
            address token,
            uint256 amount,
            uint64 periodSeconds
        );
    function claim(bytes32 spaceKey, address token) external returns (uint256 amount);
    function getTerms(bytes32 spaceKey) external view returns (Terms memory);
    function paymentTokenAllowed(address token) external view returns (bool);
    function paidThrough(bytes32 spaceKey, uint32 urbitId) external view returns (uint64);
    function claimable(bytes32 spaceKey, address token) external view returns (uint256);
}
