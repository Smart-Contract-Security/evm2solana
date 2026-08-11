// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStorage {
    enum Option {
        Short,
        Long
    }
    enum State {
        None,
        Opened,
        Closed
    }

    struct Round {
        bool defined;
        State state;
        uint256 sPrice;
        uint256 lPrice;
        uint256 sold;
        uint256 supply;
    }

    struct Referral {
        bool defined;
        bool enabled;
        uint256 firstRefRate;
        uint256 secondRefRate;
    }

    function open() external;
    function close() external;
    function setRound(uint256 sPrice_, uint256 lPrice_, uint256 supply_) external;
    function setRefRate(uint256 firstRefRate_, uint256 secondRefRate_) external;
    function setupReferrals(
        address[] calldata refs_,
        uint256[] calldata firstRefRate_,
        uint256[] calldata secodRefFunds_
    ) external;
    function updateRoundPrice(uint256 index_, uint256 sPrice_, uint256 lPrice_) external;
    function updateRoundSupply(uint256 index_, uint256 supply_) external;
    function openRound(uint256 index_) external;
    function closeRound(uint256 index_) external;
    function setAuth(address user_, bool value_) external;
    function setAuthBatch(address[] calldata users_, bool[] calldata values_) external;
    function setMax(uint256 amount_) external;
    function setMin(uint256 amount_) external;
    function setAuthLimit(uint256 amount_) external;
    function setTreasury(address treasury_) external;
    function setState(
        address user_,
        address token_,
        uint256 amount_,
        uint256 sold_,
        address ref_,
        uint256 fReward_,
        uint256 sReward_
    ) external;
    function enableReferral(address ref_) external;
    function disableReferral(address ref_) external;
    function claimRef(address[] calldata tokens_) external;
    function recoverCoin() external;
    function recoverErc20(address token_, uint256 amount_) external;
    function getTreasury() external view returns (address);
    function getMax() external view returns (uint256);
    function getMin() external view returns (uint256);
    function getRoundsCount() external view returns (uint256);
    function getCurrentRound() external view returns (uint256);
    function getRound(uint256 index_) external view returns (Round memory);
    function getTotalSold() external view returns (uint256);
    function balanceOf(uint256 round_, address user_) external view returns (uint256);
    function refBalanceOf(address token_, address user_) external view returns (uint256);
    function limitOf(address user_) external view returns (uint256);
    function maxLimitOf(address user_) external view returns (uint256);
    function getAuthLimit() external view returns (uint256);
    function getRefRates() external view returns (uint256, uint256);
    function getRef(address user_, address ref_) external view returns (address);
    function getRefRates(address ref_) external view returns (uint256, uint256);
    function isActive() external view returns (bool);
    function isInactive() external view returns (bool);
    function getPrice(Option option_) external view returns (uint256);
    function isAuth(address user_) external view returns (bool);
}
