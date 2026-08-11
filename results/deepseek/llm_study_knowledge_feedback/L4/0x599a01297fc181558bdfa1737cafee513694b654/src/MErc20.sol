// SPDX-License-Identifier: BSD-3-Clause

import {AccountMeta, AccountInfo} from 'solana';

// Define interfaces locally since they are not found
interface ComptrollerInterface {
    // Add required functions as needed
}

interface InterestRateModel {
    // Add required functions as needed
}

interface MTokenInterface {
    // Add required functions as needed
}

interface EIP20Interface {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}

interface EIP20NonStandardInterface {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external;
    function transferFrom(address from, address to, uint64 amount) external;
}

interface MErc20Interface {
    function mint(uint64 mintAmount) external returns (uint64);
    function redeem(uint64 redeemTokens) external returns (uint64);
    function redeemUnderlying(uint64 redeemAmount) external returns (uint64);
    function borrow(uint64 borrowAmount) external returns (uint64);
    function repayBorrow(uint64 repayAmount) external returns (uint64);
    function repayBorrowBehalf(address borrower, uint64 repayAmount) external returns (uint64);
    function liquidateBorrow(address borrower, uint64 repayAmount, address mTokenCollateral) external returns (uint64);
    function sweepToken(address token) external;
    function _addReserves(uint64 addAmount) external returns (uint64);
}

/**
 * @title Moonwell's MErc20 Contract
 * @notice MTokens which wrap an SPL Token underlying
 * @author Moonwell
 */
contract MErc20 is MErc20Interface {
    address public underlying;
    address public admin;
    address public comptroller;
    address public interestRateModel;
    uint64 public initialExchangeRateMantissa;
    string public name;
    string public symbol;
    uint8 public decimals;

    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        address comptroller_,
        address interestRateModel_,
        uint64 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        // Set underlying and sanity check it
        underlying = underlying_;
        comptroller = comptroller_;
        interestRateModel = interestRateModel_;
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        admin = tx.accounts.dataAccount.key;
        EIP20Interface(underlying_).totalSupply();
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives mTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint64 mintAmount) external returns (uint64) {
        (uint64 err, ) = mintInternal(mintAmount);
        return err;
    }

    /**
     * @notice Sender redeems mTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of mTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint64 redeemTokens) external returns (uint64) {
        return redeemInternal(redeemTokens);
    }

    /**
     * @notice Sender redeems mTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(
        uint64 redeemAmount
    ) external returns (uint64) {
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint64 borrowAmount) external returns (uint64) {
        return borrowInternal(borrowAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint64 repayAmount) external returns (uint64) {
        (uint64 err, ) = repayBorrowInternal(repayAmount);
        return err;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(
        address borrower,
        uint64 repayAmount
    ) external returns (uint64) {
        (uint64 err, ) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this mToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param mTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address borrower,
        uint64 repayAmount,
        address mTokenCollateral
    ) external returns (uint64) {
        (uint64 err, ) = liquidateBorrowInternal(
            borrower,
            repayAmount,
            mTokenCollateral
        );
        return err;
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(address token) external {
        require(
            tx.accounts.dataAccount.key == admin,
            "MErc20::sweepToken: only admin can sweep tokens"
        );
        require(
            token != underlying,
            "MErc20::sweepToken: can not sweep underlying token"
        );
        uint64 balance = EIP20NonStandardInterface(token).balanceOf(address(this));
        EIP20NonStandardInterface(token).transfer(admin, balance);
    }

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount fo underlying token to add as reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _addReserves(uint64 addAmount) external returns (uint64) {
        return _addReservesInternal(addAmount);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint64) {
        EIP20Interface token = EIP20Interface(underlying);
        return token.balanceOf(address(this));
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     */
    function doTransferIn(
        address from,
        uint64 amount
    ) internal returns (uint64) {
        // Read from storage once
        address underlying_ = underlying;
        EIP20NonStandardInterface token = EIP20NonStandardInterface(
            underlying_
        );
        uint64 balanceBefore = EIP20Interface(underlying_).balanceOf(
            address(this)
        );
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // Calculate the amount that was *actually* transferred
        uint64 balanceAfter = EIP20Interface(underlying_).balanceOf(
            address(this)
        );
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     */
    function doTransferOut(
        address to,
        uint64 amount
    ) internal {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of override external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }

    // Internal functions that were previously inherited from MToken
    function mintInternal(uint64 mintAmount) internal returns (uint64, uint64) {
        // Placeholder implementation
        return (0, 0);
    }

    function redeemInternal(uint64 redeemTokens) internal returns (uint64) {
        // Placeholder implementation
        return 0;
    }

    function redeemUnderlyingInternal(uint64 redeemAmount) internal returns (uint64) {
        // Placeholder implementation
        return 0;
    }

    function borrowInternal(uint64 borrowAmount) internal returns (uint64) {
        // Placeholder implementation
        return 0;
    }

    function repayBorrowInternal(uint64 repayAmount) internal returns (uint64, uint64) {
        // Placeholder implementation
        return (0, 0);
    }

    function repayBorrowBehalfInternal(address borrower, uint64 repayAmount) internal returns (uint64, uint64) {
        // Placeholder implementation
        return (0, 0);
    }

    function liquidateBorrowInternal(address borrower, uint64 repayAmount, address mTokenCollateral) internal returns (uint64, uint64) {
        // Placeholder implementation
        return (0, 0);
    }

    function _addReservesInternal(uint64 addAmount) internal returns (uint64) {
        // Placeholder implementation
        return 0;
    }
}