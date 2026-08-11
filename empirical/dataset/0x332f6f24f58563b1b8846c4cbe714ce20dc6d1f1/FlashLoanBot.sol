// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    SIMPLE AAVE FLASHLOAN EXAMPLE
    TESTNET VERSION
*/

interface IERC20 {
    function approve(address spender, uint amount)
        external
        returns (bool);

    function balanceOf(address account)
        external
        view
        returns (uint);
}

interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract FlashLoanBot is IFlashLoanSimpleReceiver {

    address public owner;

    /*
        AAVE V3 POOL (SEPOLIA)
        Replace if needed later
    */
    address public POOL =
        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // START FLASHLOAN
    function requestFlashLoan(
        address token,
        uint amount
    ) external onlyOwner {

        IPool(POOL).flashLoanSimple(
            address(this),
            token,
            amount,
            "",
            0
        );
    }

    /*
        THIS FUNCTION RUNS AUTOMATICALLY
        AFTER RECEIVING FLASHLOAN
    */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata
    ) external override returns (bool) {

        /*
            HERE YOU CAN:
            - arbitrage
            - swaps
            - trading
            - liquidation
        */

        uint totalDebt = amount + premium;

        // approve repayment
        IERC20(asset).approve(
            POOL,
            totalDebt
        );

        return true;
    }

    // CHECK TOKEN BALANCE
    function getTokenBalance(address token)
        public
        view
        returns(uint)
    {
        return IERC20(token)
            .balanceOf(address(this));
    }
}