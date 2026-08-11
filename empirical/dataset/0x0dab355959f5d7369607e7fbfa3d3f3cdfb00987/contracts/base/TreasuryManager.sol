// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Upgradeable contracts for initialization and access control.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
// Uniswap V2 interfaces for interacting with the router and factory.
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
// Standard ERC20 interface for token interactions.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./errors/TreasuryManagerErrors.sol";
import "./events/TreasuryManagerEvents.sol";

/** 
 * @title TreasuryManager (Upgradeable)
 * @notice This contract collects UNIT token taxes, swaps them for ETH via Uniswap V2,
 * and distributes the ETH to designated addresses. It is upgradeable and uses
 * role-based access control.
 * @dev swapTax can only be called by accounts with the MANAGER_ROLE,
 * and the swap process is done using Uniswap V2 functions.
 */
contract TreasuryManager is Initializable, AccessControlUpgradeable, TreasuryManagerEvents {
    /** 
     * Define a role for managers who can perform administrative tasks.
     */
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /** 
     * The UNIT token address whose taxes will be swapped.
     */
    address public unitToken;

    /** 
     * Instance of the Uniswap V2 router for swapping tokens.
     */
    IUniswapV2Router02 public router;

    /** 
     * The address of the UNIT/ETH liquidity pair on Uniswap.
     */
    address public pair;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /** 
     * @notice Initialize function (replaces constructor for upgradeable contracts).
     * @param _unitToken The address of the UNIT token.
     */
    function initialize(address _unitToken) public initializer {
        /** Initialize AccessControl functionality. */
        __AccessControl_init();
        
        /** Ensure the UNIT token address is valid. */
        if (_unitToken == address(0)) {
            revert ErrorInvalidUnitToken();
        }
        unitToken = _unitToken;

        /** Grant the default admin role and manager role to the deployer. */
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    /** 
     * @notice Sets the Uniswap V2 router address and creates the UNIT/WETH pair if it doesn't exist.
     * @param _router The Uniswap V2 router address.
     */
    function setRouterAddress(
        address _router
    ) external onlyRole(MANAGER_ROLE) {
        /** Validate the provided router address. */
        if (_router == address(0)) {
            revert ErrorInvalidRouterAddress();
        }
        /** Cast the address to the IUniswapV2Router02 interface. */
        router = IUniswapV2Router02(_router);

        /** Retrieve the factory and WETH addresses from the router. */
        address factory = router.factory();
        address weth = router.WETH();

        /** Attempt to get the existing UNIT/WETH pair address. */
        pair = IUniswapV2Factory(factory).getPair(unitToken, weth);
        /** If the pair does not exist, create a new one. */
        if (pair == address(0)) {
            pair = IUniswapV2Factory(factory).createPair(unitToken, weth);
            emit PairCreated(pair);
        }
        /** Emit event for updating the router address. */
        emit RouterUpdated(_router);
    }

    /** 
     * @notice Swaps a specified amount of UNIT tokens for ETH and sends the ETH to the receiving address.
     * @dev This function can only be called by accounts with the MANAGER_ROLE.
     * @param receiver The address that will receive the swapped ETH.
     * @param amount The amount of UNIT tokens to swap.
     */
    function swapTax(
        address receiver,
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        /** Ensure the receiving address is valid. */
        if (receiver == address(0)) {
            revert ErrorInvalidReceivingAddress();
        }
        /** Perform the internal token swap. */
        _swapTokensForETH(amount, receiver);
    }

    /** 
     * @dev Internal function to perform the token swap using Uniswap V2.
     * Uses swapExactTokensForETHSupportingFeeOnTransferTokens to support fee-on-transfer tokens.
     * Measures the ETH balance change of the contract to determine the amount received.
     * @param amount The amount of UNIT tokens to swap.
     * @param recipient The address to receive the ETH.
     */
    function _swapTokensForETH(uint256 amount, address recipient) private {
        /** Check that the contract holds enough UNIT tokens. */
        if (IERC20(unitToken).balanceOf(address(this)) < amount) {
            revert ErrorInsufficientTokenBalance();
        }

        /** Setup the swap path: UNIT token -> WETH (which represents ETH). */
        address[] memory path = new address[](2);
        path[0] = unitToken;
        path[1] = router.WETH();

        /** Approve the router to spend the specified amount of UNIT tokens. */
        IERC20(unitToken).approve(address(router), amount);

        /** Estimate the amount of ETH that will be received. */
        uint[] memory amountsOut = router.getAmountsOut(amount, path);
        uint expectedEth = amountsOut[1];
        /** Set a minimum acceptable amount at 95% of the expected output (allowing 5% slippage). */
        uint minEth = (expectedEth * 95) / 100;

        /** Record the contract's ETH balance before the swap. */
        uint256 balanceBefore = address(this).balance;

        /** Execute the token swap while supporting fee-on-transfer tokens. */
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            minEth,
            path,
            address(this),
            block.timestamp
        );

        /** Calculate the amount of ETH received by comparing balances before and after the swap. */
        uint256 balanceAfter = address(this).balance;
        uint256 amountOut = balanceAfter - balanceBefore;

        /** Transfer the received ETH to the recipient. */
        payable(recipient).transfer(amountOut);

        /** Emit an event logging the swap details. */
        emit TokensSwapped(amount, amountOut, recipient);
    }

    /** 
     * @notice Rescue any ERC20 tokens that might be accidentally sent to this contract.
     * @param _token The address of the ERC20 token to rescue.
     * @param _to The address that will receive the rescued tokens.
     * @param amount The amount of tokens to transfer.
     */
    function rescueTokens(
        address _token,
        address _to,
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        /** Validate the recipient address. */
        if (_to == address(0)) revert ErrorInvalidRecipient();
        /** Transfer the tokens from this contract to the specified recipient. */
        IERC20(_token).transfer(_to, amount);
    }

    /** 
     * @notice Rescue any ETH that might be accidentally sent to this contract.
     * @param _to The recipient address.
     * @param amount The amount of ETH to send.
     */
    function rescueETH(
        address payable _to,
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        /** Validate the recipient address. */
        if (_to == address(0)) revert ErrorInvalidRecipient();
        /** Attempt to transfer ETH using a low-level call. */
        (bool success, ) = _to.call{value: amount}("");
        if (!success) revert ErrorETHTransferFailed();
    }

    /** 
     * Allow the contract to receive ETH (for example, from Uniswap swaps).
     */
    receive() external payable {}
}
